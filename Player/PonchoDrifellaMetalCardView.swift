// ∅ 2026 lil org

import AppKit
import Foundation
import ImageIO
import MetalKit
import os
import simd

private let ponchoDrifellaLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "org.lil.nft-player",
    category: "PonchoDrifellaMetal"
)

final class PonchoDrifellaMetalCardView: NSView {

    static let cardAspectRatio = CGFloat(1000.0 / 1400.0)
    static let cardViewportInset = CGFloat(23)
    private static let pointerTrackingInterval: TimeInterval = 1.0 / 30.0

    private var metalView: MTKView?
    private var renderer: PonchoDrifellaMetalRenderer?
    private var trackingArea: NSTrackingArea?
    private var windowFocusObservers = [NSObjectProtocol]()
    private var pointerTrackingTimer: Timer?
    private var lastPolledScreenLocation: CGPoint?
    private var isDisplayed = false

    override var isHidden: Bool {
        didSet {
            updatePointerTrackingTimer()
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        configureMetalView()
    }

    required init?(coder: NSCoder) {
        fatalError("yo")
    }

    deinit {
        removeWindowFocusObservers()
        stopPointerTrackingTimer()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if window == nil {
            removeWindowFocusObservers()
            stopPointerTrackingTimer()
            renderer?.stop()
        } else {
            installWindowFocusObservers()
            renderer?.start()
            updatePointerTrackingTimer()
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseEnteredAndExited, .mouseMoved, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
    }

    override func mouseMoved(with event: NSEvent) {
        updatePointer(with: event)
    }

    override func mouseEntered(with event: NSEvent) {
        updatePointer(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        updatePointer(with: event)
    }

    func display(tokenId: String) {
        guard let tokenID = Int(tokenId) else { return }
        isDisplayed = true
        renderer?.display(tokenID: tokenID)
        updatePointerTrackingTimer()
    }

    func stop() {
        isDisplayed = false
        stopPointerTrackingTimer()
        renderer?.stop()
    }

    static func resetMotionCalibration() {
        PonchoDrifellaPointerStateTracker.shared.reset()
    }

    static func cardContentRect(in size: CGSize) -> CGRect {
        guard size.width > 0, size.height > 0 else { return .zero }
        let availableWidth = max(size.width - cardViewportInset * 2, 1)
        let availableHeight = max(size.height - cardViewportInset * 2, 1)
        let cardWidth = min(availableWidth, availableHeight * cardAspectRatio)
        let cardHeight = cardWidth / cardAspectRatio
        let minX = (size.width - cardWidth) / 2
        let minY = (size.height - cardHeight) / 2
        return CGRect(x: minX, y: minY, width: cardWidth, height: cardHeight)
    }

    private func configureMetalView() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            ponchoDrifellaLogger.error("Metal device is unavailable")
            return
        }
        guard let renderer = PonchoDrifellaMetalRenderer(device: device) else {
            ponchoDrifellaLogger.error("Metal renderer initialization failed")
            return
        }

        let metalView = MTKView(frame: bounds, device: device)
        metalView.translatesAutoresizingMaskIntoConstraints = false
        metalView.layer?.backgroundColor = NSColor.clear.cgColor
        metalView.clearColor = MTLClearColorMake(0, 0, 0, 0)
        metalView.colorPixelFormat = .bgra8Unorm
        metalView.framebufferOnly = true
        metalView.enableSetNeedsDisplay = true
        metalView.isPaused = true
        metalView.preferredFramesPerSecond = 30
        metalView.delegate = renderer
        addSubview(metalView)

        NSLayoutConstraint.activate([
            metalView.leadingAnchor.constraint(equalTo: leadingAnchor),
            metalView.trailingAnchor.constraint(equalTo: trailingAnchor),
            metalView.topAnchor.constraint(equalTo: topAnchor),
            metalView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        renderer.attach(to: metalView)
        self.metalView = metalView
        self.renderer = renderer
    }

    private func updatePointer(with event: NSEvent) {
        if let window {
            lastPolledScreenLocation = window.convertPoint(toScreen: event.locationInWindow)
        }
        let location = convert(event.locationInWindow, from: nil)
        renderer?.updatePointer(location: location, in: bounds.size)
    }

    private func installWindowFocusObservers() {
        removeWindowFocusObservers()

        guard let window else { return }

        let notificationCenter = NotificationCenter.default
        let observerSpecs: [(Notification.Name, Any?)] = [
            (NSWindow.didBecomeKeyNotification, window),
            (NSWindow.didResignKeyNotification, window),
            (NSApplication.didBecomeActiveNotification, nil),
            (NSApplication.didResignActiveNotification, nil)
        ]
        windowFocusObservers = observerSpecs.map { name, object in
            notificationCenter.addObserver(
                forName: name,
                object: object,
                queue: .main
            ) { [weak self] _ in
                self?.updatePointerTrackingTimer()
            }
        }
    }

    private func removeWindowFocusObservers() {
        windowFocusObservers.forEach(NotificationCenter.default.removeObserver)
        windowFocusObservers = []
    }

    private var shouldPollPointerOutsideWindow: Bool {
        isDisplayed
            && !isHidden
            && window?.isKeyWindow == true
            && NSApplication.shared.isActive
    }

    private func updatePointerTrackingTimer() {
        if shouldPollPointerOutsideWindow {
            startPointerTrackingTimer()
        } else {
            stopPointerTrackingTimer()
        }
    }

    private func startPointerTrackingTimer() {
        guard pointerTrackingTimer == nil else { return }

        pollPointerFromScreen()

        let timer = Timer(timeInterval: Self.pointerTrackingInterval, repeats: true) { [weak self] _ in
            self?.pollPointerFromScreen()
        }
        RunLoop.main.add(timer, forMode: .common)
        pointerTrackingTimer = timer
    }

    private func stopPointerTrackingTimer() {
        pointerTrackingTimer?.invalidate()
        pointerTrackingTimer = nil
        lastPolledScreenLocation = nil
    }

    private func pollPointerFromScreen() {
        guard shouldPollPointerOutsideWindow, let window else {
            updatePointerTrackingTimer()
            return
        }

        let screenLocation = NSEvent.mouseLocation
        guard screenLocation != lastPolledScreenLocation else { return }

        lastPolledScreenLocation = screenLocation
        let windowLocation = window.convertPoint(fromScreen: screenLocation)
        let location = convert(windowLocation, from: nil)
        renderer?.updatePointer(location: location, in: bounds.size)
    }
}

private struct PonchoDrifellaVertex {
    let position: SIMD2<Float>
    let uv: SIMD2<Float>
}

private struct PonchoDrifellaUniforms {
    var pointer: SIMD2<Float>
    var background: SIMD2<Float>
    var cardSize: SIMD2<Float>
    var pointerFromCenter: Float
    var opacity: Float
    var maskUsesAlpha: Float
    var effectKind: Int32
    var glowKind: Int32
    var padding: Float = 0
}

private struct PonchoDrifellaLoadedTextures {
    let face: MTLTexture
    let foil: MTLTexture
    let textureMask: MTLTexture
    let grain: MTLTexture
    let glitter: MTLTexture
    let hasEffects: Bool
    let maskUsesAlpha: Bool
}

private struct PonchoDrifellaPointerState {
    var pointer = SIMD2<Float>(0.5, 0.5)
    var background = SIMD2<Float>(0.5, 0.5)
    var pointerFromCenter: Float = 0
    var effectOpacity: Float = 0.99
}

private final class PonchoDrifellaPointerStateTracker {
    static let shared = PonchoDrifellaPointerStateTracker()

    private(set) var state = PonchoDrifellaPointerState()

    private init() {}

    func update(location: CGPoint, in size: CGSize) {
        guard size.width > 0, size.height > 0 else {
            reset()
            return
        }

        let x = Float(min(max(location.x / size.width, 0), 1))
        let y = Float(min(max(1 - location.y / size.height, 0), 1))
        let pointer = SIMD2<Float>(x, y)
        let centered = pointer - SIMD2<Float>(0.5, 0.5)
        state.pointer = clamped(pointer, lowerBound: 0.04, upperBound: 0.96)
        state.background = clamped(SIMD2<Float>(0.5, 0.5) + centered * 0.32, lowerBound: 0.25, upperBound: 0.75)
        state.pointerFromCenter = min(length(centered) * 2, 1)
        state.effectOpacity = 0.99
    }

    func reset() {
        state = PonchoDrifellaPointerState()
    }

    private func clamped(_ value: SIMD2<Float>, lowerBound: Float, upperBound: Float) -> SIMD2<Float> {
        SIMD2<Float>(
            min(max(value.x, lowerBound), upperBound),
            min(max(value.y, lowerBound), upperBound)
        )
    }
}

private final class PonchoDrifellaMetalRenderer: NSObject, MTKViewDelegate {

    private weak var metalView: MTKView?
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private let placeholderTexture: MTLTexture
    private let textureQueue = DispatchQueue(label: "org.lil.nft-player.poncho-textures", qos: .userInitiated)
    private let textureLoader: MTKTextureLoader
    private let pointerTracker = PonchoDrifellaPointerStateTracker.shared

    private var currentTokenID: Int?
    private var loadGeneration = UUID()
    private var metadata = PonchoDrifellaCardMetadata.metadata(for: 1)
    private var textures: PonchoDrifellaLoadedTextures?

    init?(device: MTLDevice) {
        guard let commandQueue = device.makeCommandQueue() else {
            ponchoDrifellaLogger.error("Metal command queue creation failed")
            return nil
        }
        guard let placeholderTexture = Self.makeSolidTexture(device: device, red: 0, green: 0, blue: 0, alpha: 255) else {
            ponchoDrifellaLogger.error("Metal placeholder texture creation failed")
            return nil
        }
        guard let library = device.makeDefaultLibrary() else {
            ponchoDrifellaLogger.error("Default Metal library is unavailable; check that PonchoDrifellaShaders.metal is in the macOS target sources")
            return nil
        }
        guard let vertexFunction = library.makeFunction(name: "ponchoDrifellaVertex"),
              let fragmentFunction = library.makeFunction(name: "ponchoDrifellaFragment") else {
            ponchoDrifellaLogger.error("Poncho Metal shader functions are missing from the default library")
            return nil
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

        do {
            self.pipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            ponchoDrifellaLogger.error("Poncho Metal pipeline creation failed: \(String(describing: error), privacy: .public)")
            return nil
        }

        self.device = device
        self.commandQueue = commandQueue
        self.placeholderTexture = placeholderTexture
        self.textureLoader = MTKTextureLoader(device: device)
        super.init()
    }

    func attach(to metalView: MTKView) {
        self.metalView = metalView
    }

    func display(tokenID: Int) {
        let clampedTokenID = min(max(tokenID, 1), PonchoDrifellaCardMetadata.tokenCount)
        if currentTokenID == clampedTokenID, textures != nil {
            start()
            metalView?.draw()
            return
        }

        currentTokenID = clampedTokenID
        metadata = PonchoDrifellaCardMetadata.metadata(for: clampedTokenID)
        textures = nil
        metalView?.draw()

        let generation = UUID()
        loadGeneration = generation
        PonchoDrifellaAssetCache.shared.loadFace(for: clampedTokenID) { [weak self] faceURL in
            guard let self,
                  self.currentTokenID == clampedTokenID,
                  self.loadGeneration == generation,
                  let faceURL else {
                return
            }
            self.loadFaceTexture(from: faceURL, tokenID: clampedTokenID, generation: generation)
        }
        PonchoDrifellaAssetCache.shared.loadAssets(for: clampedTokenID) { [weak self] assetURLs in
            guard let self,
                  self.currentTokenID == clampedTokenID,
                  self.loadGeneration == generation,
                  let assetURLs else {
                return
            }
            self.loadTextures(from: assetURLs, generation: generation)
        }
        PonchoDrifellaAssetCache.shared.prefetch(around: clampedTokenID, radius: 2)
        start()
    }

    func start() {
        guard metalView?.window != nil else { return }
        metalView?.draw()
    }

    func stop() {
        pointerTracker.reset()
        metalView?.draw()
    }

    func updatePointer(location: CGPoint, in size: CGSize) {
        pointerTracker.update(location: location, in: size)
        metalView?.draw()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        view.draw()
    }

    func draw(in view: MTKView) {
        guard let textures,
              let renderPassDescriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }

        let cardRect = cardRect(in: view.bounds.size)
        let vertices = cardVertices(in: view.bounds.size, cardRect: cardRect)
        let scale = view.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1
        let pointerState = pointerTracker.state
        var uniforms = PonchoDrifellaUniforms(
            pointer: pointerState.pointer,
            background: pointerState.background,
            cardSize: SIMD2<Float>(
                Float(cardRect.width * scale),
                Float(cardRect.height * scale)
            ),
            pointerFromCenter: pointerState.pointerFromCenter,
            opacity: textures.hasEffects ? pointerState.effectOpacity : 0,
            maskUsesAlpha: textures.maskUsesAlpha ? 1 : 0,
            effectKind: Int32(metadata.effectKind),
            glowKind: Int32(metadata.glowKind)
        )

        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBytes(
            vertices,
            length: MemoryLayout<PonchoDrifellaVertex>.stride * vertices.count,
            index: 0
        )
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<PonchoDrifellaUniforms>.stride, index: 0)
        encoder.setFragmentTexture(textures.face, index: 0)
        encoder.setFragmentTexture(textures.foil, index: 1)
        encoder.setFragmentTexture(textures.textureMask, index: 2)
        encoder.setFragmentTexture(textures.grain, index: 3)
        encoder.setFragmentTexture(textures.glitter, index: 4)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: vertices.count)
        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private func cardRect(in size: CGSize) -> CGRect {
        PonchoDrifellaMetalCardView.cardContentRect(in: size)
    }

    private func cardVertices(in size: CGSize, cardRect: CGRect) -> [PonchoDrifellaVertex] {
        guard size.width > 0, size.height > 0, !cardRect.isEmpty else { return [] }

        let minX = cardRect.minX
        let maxX = cardRect.maxX
        let minY = cardRect.minY
        let maxY = cardRect.maxY

        func ndc(_ x: CGFloat, _ y: CGFloat) -> SIMD2<Float> {
            SIMD2<Float>(
                Float((x / size.width) * 2 - 1),
                Float(1 - (y / size.height) * 2)
            )
        }

        return [
            PonchoDrifellaVertex(position: ndc(minX, minY), uv: SIMD2<Float>(0, 0)),
            PonchoDrifellaVertex(position: ndc(minX, maxY), uv: SIMD2<Float>(0, 1)),
            PonchoDrifellaVertex(position: ndc(maxX, minY), uv: SIMD2<Float>(1, 0)),
            PonchoDrifellaVertex(position: ndc(maxX, maxY), uv: SIMD2<Float>(1, 1))
        ]
    }

    private func loadFaceTexture(from url: URL, tokenID: Int, generation: UUID) {
        textureQueue.async { [weak self] in
            guard let self else { return }

            do {
                let faceTexture = try self.makeTexture(from: url)
                let loadedTextures = PonchoDrifellaLoadedTextures(
                    face: faceTexture,
                    foil: self.placeholderTexture,
                    textureMask: self.placeholderTexture,
                    grain: self.placeholderTexture,
                    glitter: self.placeholderTexture,
                    hasEffects: false,
                    maskUsesAlpha: true
                )

                DispatchQueue.main.async { [weak self] in
                    guard let self,
                          self.currentTokenID == tokenID,
                          self.loadGeneration == generation,
                          self.textures == nil else {
                        return
                    }

                    self.textures = loadedTextures
                    self.metalView?.draw()
                }
            } catch {
                ponchoDrifellaLogger.error("Poncho face texture load failed for token \(tokenID, privacy: .public): \(String(describing: error), privacy: .public)")
            }
        }
    }

    private func loadTextures(from assetURLs: PonchoDrifellaAssetURLs, generation: UUID) {
        let preloadedFace = textures?.face
        textureQueue.async { [weak self] in
            guard let self else { return }

            do {
                let loadedTextures = try PonchoDrifellaLoadedTextures(
                    face: preloadedFace ?? self.makeTexture(from: assetURLs.face),
                    foil: self.makeTexture(from: assetURLs.foil, generateMipmaps: true),
                    textureMask: self.makeTexture(from: assetURLs.textureMask, generateMipmaps: true),
                    grain: self.makeTexture(from: assetURLs.grain, generateMipmaps: true),
                    glitter: self.makeTexture(from: assetURLs.glitter, generateMipmaps: true),
                    hasEffects: true,
                    maskUsesAlpha: Self.imageHasAlpha(at: assetURLs.textureMask)
                )

                DispatchQueue.main.async { [weak self] in
                    guard let self,
                          self.currentTokenID == assetURLs.tokenID,
                          self.loadGeneration == generation else {
                        return
                    }

                    self.textures = loadedTextures
                    self.metalView?.draw()
                }
            } catch {
                ponchoDrifellaLogger.error("Poncho effect texture load failed for token \(assetURLs.tokenID, privacy: .public): \(String(describing: error), privacy: .public)")
                PonchoDrifellaAssetCache.shared.invalidate(tokenID: assetURLs.tokenID)
            }
        }
    }

    private func makeTexture(from url: URL, generateMipmaps: Bool = false) throws -> MTLTexture {
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            throw CocoaError(.fileReadCorruptFile)
        }

        do {
            return try makeTexture(from: image, generateMipmaps: generateMipmaps)
        } catch {
            let originalError = error
            guard let normalizedImage = Self.normalizedImage(from: image) else {
                throw originalError
            }

            do {
                return try makeTexture(from: normalizedImage, generateMipmaps: generateMipmaps)
            } catch {
                ponchoDrifellaLogger.error(
                    "Poncho texture normalization failed for \(url.lastPathComponent, privacy: .public): \(String(describing: error), privacy: .public)"
                )
                throw originalError
            }
        }
    }

    private func makeTexture(from image: CGImage, generateMipmaps: Bool = false) throws -> MTLTexture {
        let options: [MTKTextureLoader.Option: Any] = [
            .SRGB: false,
            .generateMipmaps: NSNumber(value: generateMipmaps),
            .textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue),
            .textureStorageMode: NSNumber(value: MTLStorageMode.private.rawValue)
        ]
        return try textureLoader.newTexture(cgImage: image, options: options)
    }

    private static func normalizedImage(from image: CGImage) -> CGImage? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }

        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    private static func imageHasAlpha(at url: URL) -> Bool {
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            return false
        }

        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast:
            return false
        default:
            return true
        }
    }

    private static func makeSolidTexture(device: MTLDevice, red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: 1,
            height: 1,
            mipmapped: false
        )
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }

        var pixel = (red, green, blue, alpha)
        texture.replace(
            region: MTLRegionMake2D(0, 0, 1, 1),
            mipmapLevel: 0,
            withBytes: &pixel,
            bytesPerRow: 4
        )
        return texture
    }
}
