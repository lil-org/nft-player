// ∅ 2026 lil org

import CoreMotion
import Foundation
import ImageIO
import MetalKit
import UIKit
import os
import simd

private let ponchoDrifellaLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "org.lil.nft-player",
    category: "PonchoDrifellaMetal"
)

final class PonchoDrifellaMetalCardView: UIView {

    static let cardAspectRatio = CGFloat(1000.0 / 1400.0)
    static let cardViewportInset = CGFloat(23)

    private var metalView: MTKView?
    private var renderer: PonchoDrifellaMetalRenderer?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        configureMetalView()
    }

    required init?(coder: NSCoder) {
        fatalError("yo")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()

        if window == nil {
            renderer?.stop()
        } else {
            renderer?.start()
        }
    }

    func display(tokenId: String) {
        guard let tokenID = Int(tokenId) else { return }
        renderer?.display(tokenID: tokenID)
    }

    func stop() {
        renderer?.stop()
    }

    static func resetMotionCalibration() {
        PonchoDrifellaMotionTracker.shared.resetCalibration()
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
        metalView.backgroundColor = .clear
        metalView.isOpaque = false
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

private struct PonchoDrifellaMotionState {
    var pointer = SIMD2<Float>(0.5, 0.5)
    var background = SIMD2<Float>(0.5, 0.5)
    var pointerFromCenter: Float = 0
    var effectOpacity: Float = 0
}

private final class PonchoDrifellaMotionTracker {

    static let shared = PonchoDrifellaMotionTracker()
    private static let fixedLightPosition = SIMD2<Float>(0.5, 0.5)
    private static let pointerTravel = SIMD2<Float>(0.42, 0.42)
    private static let backgroundTravel = SIMD2<Float>(0.13, 0.17)

    private let motionManager = CMMotionManager()
    private var neutralGravity: CMAcceleration?
    private var state = PonchoDrifellaMotionState()
    private var observers = [UUID: () -> Void]()
    private var applicationIsActive = UIApplication.shared.applicationState == .active
    private var applicationLifecycleObservers = [NSObjectProtocol]()

    private init() {
        installApplicationLifecycleObservers()
    }

    deinit {
        applicationLifecycleObservers.forEach(NotificationCenter.default.removeObserver)
    }

    func addObserver(_ observer: @escaping () -> Void) -> UUID {
        let id = UUID()
        observers[id] = observer
        return id
    }

    func removeObserver(id: UUID) {
        observers[id] = nil
        if observers.isEmpty {
            stopDeviceMotionUpdates(resetCalibration: false)
        }
    }

    func start() {
        guard applicationIsActive else {
            resetCalibration(notifyObservers: false)
            return
        }
        guard motionManager.isDeviceMotionAvailable else {
            if state.effectOpacity == 0 {
                updateEffect(rawX: 0, rawY: 0, smooth: false)
            }
            return
        }
        guard !motionManager.isDeviceMotionActive else { return }

        motionManager.deviceMotionUpdateInterval = 1.0 / 30.0
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self,
                  self.applicationIsActive,
                  !self.observers.isEmpty,
                  let motion else {
                return
            }
            self.handleMotion(motion)
        }
    }

    func snapshot() -> PonchoDrifellaMotionState {
        state
    }

    func resetCalibration() {
        resetCalibration(notifyObservers: applicationIsActive)
    }

    private func resetCalibration(notifyObservers: Bool) {
        neutralGravity = nil
        updateEffect(rawX: 0, rawY: 0, smooth: false, notifyObservers: notifyObservers)
    }

    private func installApplicationLifecycleObservers() {
        let notificationCenter = NotificationCenter.default
        let inactiveNotifications: [NSNotification.Name] = [
            UIApplication.willResignActiveNotification,
            UIApplication.didEnterBackgroundNotification
        ]

        applicationLifecycleObservers = inactiveNotifications.map { name in
            notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.suspendForApplicationLifecycle()
            }
        }
        applicationLifecycleObservers.append(
            notificationCenter.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.resumeFromApplicationLifecycle()
            }
        )
    }

    private func suspendForApplicationLifecycle() {
        guard applicationIsActive else { return }

        applicationIsActive = false
        stopDeviceMotionUpdates(resetCalibration: true, notifyObservers: false)
    }

    private func resumeFromApplicationLifecycle() {
        applicationIsActive = true
        resetCalibration()

        guard !observers.isEmpty else { return }
        start()
    }

    private func stopDeviceMotionUpdates(resetCalibration: Bool, notifyObservers: Bool = true) {
        motionManager.stopDeviceMotionUpdates()

        if resetCalibration {
            self.resetCalibration(notifyObservers: notifyObservers)
        }
    }

    private func handleMotion(_ motion: CMDeviceMotion) {
        if neutralGravity == nil {
            neutralGravity = motion.gravity
            if state.effectOpacity == 0 {
                updateEffect(rawX: 0, rawY: 0, smooth: false)
            }
            return
        }

        guard let neutralGravity else { return }

        let rawX = Self.clamped(Float((motion.gravity.x - neutralGravity.x) * 4.0))
        let rawY = Self.clamped(Float((neutralGravity.z - motion.gravity.z) * 4.8))
        updateEffect(rawX: rawX, rawY: rawY, smooth: true)
    }

    private func updateEffect(rawX: Float, rawY: Float, smooth: Bool, notifyObservers: Bool = true) {
        let cardTilt = SIMD2<Float>(Self.clamped(rawX), Self.clamped(rawY))
        let cardOffset = cardTilt * Self.pointerTravel
        let backgroundOffset = cardTilt * Self.backgroundTravel

        // Keep the light fixed in screen space; tilt moves the card surface under it.
        let targetPointer = Self.clamped(
            Self.fixedLightPosition - cardOffset,
            lowerBound: 0.04,
            upperBound: 0.96
        )
        let targetBackground = Self.clamped(
            Self.fixedLightPosition - backgroundOffset,
            lowerBound: 0.25,
            upperBound: 0.75
        )

        let smoothing: Float = smooth ? 0.30 : 1
        state.pointer += (targetPointer - state.pointer) * smoothing
        state.pointer = Self.clamped(state.pointer, lowerBound: 0.01, upperBound: 0.99)

        state.background += (targetBackground - state.background) * smoothing
        state.background = Self.clamped(state.background, lowerBound: 0.12, upperBound: 0.88)
        state.pointerFromCenter = min(length(cardTilt), 1)
        state.effectOpacity = 0.99
        if notifyObservers {
            self.notifyObservers()
        }
    }

    private func notifyObservers() {
        guard applicationIsActive else { return }
        Array(observers.values).forEach { $0() }
    }

    private static func clamped(_ value: Float) -> Float {
        min(max(value, -1), 1)
    }

    private static func clamped(_ value: SIMD2<Float>, lowerBound: Float, upperBound: Float) -> SIMD2<Float> {
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
    private let motionTracker = PonchoDrifellaMotionTracker.shared

    private var currentTokenID: Int?
    private var loadGeneration = UUID()
    private var metadata = PonchoDrifellaCardMetadata.metadata(for: 1)
    private var textures: PonchoDrifellaLoadedTextures?
    private var motionObserverID: UUID?

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
            ponchoDrifellaLogger.error("Default Metal library is unavailable; check that PonchoDrifellaShaders.metal is in the iOS target sources")
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

    deinit {
        stop()
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

            PonchoDrifellaAssetCache.shared.loadAssets(for: clampedTokenID) { [weak self] assetURLs in
                guard let self,
                      self.currentTokenID == clampedTokenID,
                      self.loadGeneration == generation,
                      let assetURLs else {
                    return
                }
                self.loadTextures(from: assetURLs, generation: generation)
            }
        }
        PonchoDrifellaAssetCache.shared.prefetch(around: clampedTokenID, radius: 2)
        start()
    }

    func start() {
        guard metalView?.window != nil else { return }
        if motionObserverID == nil {
            motionObserverID = motionTracker.addObserver { [weak self] in
                self?.metalView?.draw()
            }
        }
        motionTracker.start()
        metalView?.draw()
    }

    func stop() {
        guard let motionObserverID else { return }
        motionTracker.removeObserver(id: motionObserverID)
        self.motionObserverID = nil
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
        let scaleX = view.bounds.width > 0 ? view.drawableSize.width / view.bounds.width : view.contentScaleFactor
        let scaleY = view.bounds.height > 0 ? view.drawableSize.height / view.bounds.height : view.contentScaleFactor
        let motionState = motionTracker.snapshot()
        var uniforms = PonchoDrifellaUniforms(
            pointer: motionState.pointer,
            background: motionState.background,
            cardSize: SIMD2<Float>(
                Float(cardRect.width * scaleX),
                Float(cardRect.height * scaleY)
            ),
            pointerFromCenter: motionState.pointerFromCenter,
            opacity: textures.hasEffects ? motionState.effectOpacity : 0,
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
