// ∅ 2026 lil org

import CoreMotion
import Foundation
import ImageIO
import MetalKit
import UIKit
import os
import simd

private let ponchoDrifellaLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "org.lil.nft-folder",
    category: "PonchoDrifellaMetal"
)

final class PonchoDrifellaMetalCardView: UIView {

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

    private let motionManager = CMMotionManager()
    private var neutralGravity: CMAcceleration?
    private var state = PonchoDrifellaMotionState()
    private var observers = [UUID: () -> Void]()

    private init() {}

    func addObserver(_ observer: @escaping () -> Void) -> UUID {
        let id = UUID()
        observers[id] = observer
        return id
    }

    func removeObserver(id: UUID) {
        observers[id] = nil
        if observers.isEmpty {
            motionManager.stopDeviceMotionUpdates()
        }
    }

    func start() {
        guard motionManager.isDeviceMotionAvailable else {
            if state.effectOpacity == 0 {
                updateEffect(rawX: 0, rawY: 0, smooth: false)
            }
            return
        }
        guard !motionManager.isDeviceMotionActive else { return }

        motionManager.deviceMotionUpdateInterval = 1.0 / 30.0
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            self.handleMotion(motion)
        }
    }

    func snapshot() -> PonchoDrifellaMotionState {
        state
    }

    func resetCalibration() {
        neutralGravity = nil
        updateEffect(rawX: 0, rawY: 0, smooth: false)
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

    private func updateEffect(rawX: Float, rawY: Float, smooth: Bool) {
        let targetPointer = SIMD2<Float>(
            0.5 + Self.clamped(rawX) * 0.49,
            0.5 + Self.clamped(rawY) * 0.49
        )
        let smoothing: Float = smooth ? 0.38 : 1
        state.pointer += (targetPointer - state.pointer) * smoothing
        state.pointer.x = min(max(state.pointer.x, 0.01), 0.99)
        state.pointer.y = min(max(state.pointer.y, 0.01), 0.99)

        state.background = SIMD2<Float>(
            0.37 + state.pointer.x * 0.26,
            0.33 + state.pointer.y * 0.34
        )
        state.pointerFromCenter = min(length((state.pointer - SIMD2<Float>(repeating: 0.5)) * 2), 1)
        state.effectOpacity = 0.99
        notifyObservers()
    }

    private func notifyObservers() {
        Array(observers.values).forEach { $0() }
    }

    private static func clamped(_ value: Float) -> Float {
        min(max(value, -1), 1)
    }
}

private final class PonchoDrifellaMetalRenderer: NSObject, MTKViewDelegate {

    private static let cardAspectRatio = CGFloat(1000.0 / 1400.0)
    private static let viewportInset = CGFloat(23)

    private weak var metalView: MTKView?
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private let placeholderTexture: MTLTexture
    private let textureQueue = DispatchQueue(label: "org.lil.nft-folder.poncho-textures", qos: .userInitiated)
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
        guard size.width > 0, size.height > 0 else { return .zero }
        let availableWidth = max(size.width - Self.viewportInset * 2, 1)
        let availableHeight = max(size.height - Self.viewportInset * 2, 1)
        let cardWidth = min(availableWidth, availableHeight * Self.cardAspectRatio)
        let cardHeight = cardWidth / Self.cardAspectRatio
        let minX = (size.width - cardWidth) / 2
        let minY = (size.height - cardHeight) / 2
        return CGRect(x: minX, y: minY, width: cardWidth, height: cardHeight)
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

private struct PonchoDrifellaCardMetadata {
    let effectKind: UInt8
    let glowKind: UInt8

    static var tokenCount: Int {
        assert(effectKinds.count == glowKinds.count, "Poncho metadata arrays must stay aligned")
        return min(effectKinds.count, glowKinds.count)
    }

    static func metadata(for tokenID: Int) -> PonchoDrifellaCardMetadata {
        let index = min(max(tokenID, 1), tokenCount) - 1
        return PonchoDrifellaCardMetadata(effectKind: effectKinds[index], glowKind: glowKinds[index])
    }

    private static let effectKinds: [UInt8] = [
        0, 0, 0, 0, 2, 3, 1, 0, 3, 2, 1, 0, 3, 0, 0, 3, 0, 1, 3, 3, 0, 2, 2, 3,
        3, 2, 3, 1, 2, 2, 0, 0, 3, 3, 1, 0, 1, 2, 0, 3, 2, 2, 1, 0, 1, 0, 0, 0,
        1, 2, 0, 1, 2, 2, 0, 2, 2, 0, 2, 3, 3, 0, 2, 2, 1, 2, 2, 1, 0, 0, 2, 3,
        0, 0, 3, 3, 0, 0, 0, 0, 2, 1, 1, 1, 0, 0, 0, 3, 3, 1, 0, 0, 0, 1, 0, 2,
        3, 2, 2, 1, 1, 0, 0, 3, 2, 3, 2, 0, 2, 0, 0, 1, 0, 1, 2, 0, 3, 1, 1, 0,
        0, 2, 1, 1, 1, 0, 3, 0, 2, 0, 0, 2, 2, 0, 2, 0, 0, 3, 2, 2, 2, 0, 0, 0,
        2, 0, 0, 0, 2, 3, 2, 2, 2, 2, 2, 2, 2, 0, 0, 1, 2, 0, 2, 0, 3, 2, 0, 1,
        2, 0, 2, 0, 0, 0, 2, 1, 1, 1, 1, 3, 2, 0, 2, 2, 3, 0, 0, 0, 0, 2, 1, 2,
        1, 0, 0, 0, 2, 2, 3, 3, 3, 3, 3, 3, 3, 3, 1
    ]

    private static let glowKinds: [UInt8] = [
        0, 8, 0, 9, 0, 4, 1, 5, 8, 7, 9, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2
    ]
}

private struct PonchoDrifellaAssetURLs {
    let tokenID: Int
    let face: URL
    let foil: URL
    let textureMask: URL
    let grain: URL
    let glitter: URL
}

private final class PonchoDrifellaAssetCache {

    static let shared = PonchoDrifellaAssetCache()

    private let fileManager = FileManager.default
    private let rootURL: URL
    private let baseURL = URL(string: "https://mons.shop/Poncho_Drifella")!
    private let workQueue = DispatchQueue(label: "org.lil.nft-folder.poncho-cache", qos: .utility)
    private var pendingDownloadCompletions = [String: [(Bool) -> Void]]()

    private init() {
        let applicationSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        rootURL = applicationSupportURL.appendingPathComponent("PonchoDrifellaAssets", isDirectory: true)
        try? fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)

        var resourceURL = rootURL
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try? resourceURL.setResourceValues(resourceValues)
    }

    func loadAssets(for tokenID: Int, completion: @escaping (PonchoDrifellaAssetURLs?) -> Void) {
        let assetURLs = urls(for: tokenID)
        ensureFiles(relativePaths(for: tokenID)) { didSucceed in
            DispatchQueue.main.async {
                completion(didSucceed ? assetURLs : nil)
            }
        }
    }

    func loadFace(for tokenID: Int, completion: @escaping (URL?) -> Void) {
        let path = "drifs/\(tokenID).webp"
        ensureFiles([path]) { [weak self] didSucceed in
            guard let self else { return }

            DispatchQueue.main.async {
                completion(didSucceed ? self.localURL(for: path) : nil)
            }
        }
    }

    func prefetch(around tokenID: Int, radius: Int) {
        let lowerBound = max(1, tokenID - radius)
        let upperBound = min(PonchoDrifellaCardMetadata.tokenCount, tokenID + radius)
        for id in lowerBound...upperBound where id != tokenID {
            ensureFiles(relativePaths(for: id, includesSharedAssets: false), completion: nil)
        }
    }

    func invalidate(tokenID: Int) {
        workQueue.async {
            for path in self.relativePaths(for: tokenID, includesSharedAssets: false) {
                try? self.fileManager.removeItem(at: self.localURL(for: path))
            }
        }
    }

    private func ensureFiles(_ relativePaths: [String], completion: ((Bool) -> Void)?) {
        let group = DispatchGroup()
        let statusLock = NSLock()
        var didSucceed = true

        for path in relativePaths {
            group.enter()
            ensureFile(path) { success in
                statusLock.lock()
                didSucceed = didSucceed && success
                statusLock.unlock()
                group.leave()
            }
        }

        group.notify(queue: workQueue) {
            completion?(didSucceed)
        }
    }

    private func ensureFile(_ relativePath: String, completion: @escaping (Bool) -> Void) {
        workQueue.async {
            let localURL = self.localURL(for: relativePath)
            if self.hasCachedFile(at: localURL) {
                completion(true)
                return
            }

            if self.pendingDownloadCompletions[relativePath] != nil {
                self.pendingDownloadCompletions[relativePath]?.append(completion)
                return
            }
            self.pendingDownloadCompletions[relativePath] = [completion]

            let remoteURL = self.baseURL.appendingPathComponent(relativePath)
            let task = URLSession.shared.downloadTask(with: remoteURL) { temporaryURL, response, error in
                let didSucceed = self.storeDownloadedFile(
                    from: temporaryURL,
                    response: response,
                    error: error,
                    remoteURL: remoteURL,
                    localURL: localURL
                )
                self.completeDownload(relativePath: relativePath, didSucceed: didSucceed)
            }
            task.resume()
        }
    }

    private func storeDownloadedFile(
        from temporaryURL: URL?,
        response: URLResponse?,
        error: Error?,
        remoteURL: URL,
        localURL: URL
    ) -> Bool {
        guard error == nil,
              let temporaryURL,
              (response as? HTTPURLResponse).map({ 200..<300 ~= $0.statusCode }) != false else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            ponchoDrifellaLogger.error(
                "Poncho asset download failed: \(remoteURL.absoluteString, privacy: .public), status: \(statusCode, privacy: .public), error: \(String(describing: error), privacy: .public)"
            )
            return false
        }

        do {
            try fileManager.createDirectory(
                at: localURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? fileManager.removeItem(at: localURL)
            try fileManager.moveItem(at: temporaryURL, to: localURL)
            return hasCachedFile(at: localURL)
        } catch {
            ponchoDrifellaLogger.error(
                "Poncho asset cache write failed: \(localURL.path, privacy: .public), error: \(String(describing: error), privacy: .public)"
            )
            return false
        }
    }

    private func completeDownload(relativePath: String, didSucceed: Bool) {
        workQueue.async {
            let completions = self.pendingDownloadCompletions.removeValue(forKey: relativePath) ?? []
            completions.forEach { $0(didSucceed) }
        }
    }

    private func urls(for tokenID: Int) -> PonchoDrifellaAssetURLs {
        PonchoDrifellaAssetURLs(
            tokenID: tokenID,
            face: localURL(for: "drifs/\(tokenID).webp"),
            foil: localURL(for: "foils/\(tokenID).webp"),
            textureMask: localURL(for: "textures/\(tokenID).webp"),
            grain: localURL(for: "img/grain.webp"),
            glitter: localURL(for: "img/glitter.png")
        )
    }

    private func relativePaths(for tokenID: Int, includesSharedAssets: Bool = true) -> [String] {
        var paths = [
            "drifs/\(tokenID).webp",
            "foils/\(tokenID).webp",
            "textures/\(tokenID).webp"
        ]
        if includesSharedAssets {
            paths.append(contentsOf: ["img/grain.webp", "img/glitter.png"])
        }
        return paths
    }

    private func localURL(for relativePath: String) -> URL {
        rootURL.appendingPathComponent(relativePath)
    }

    private func hasCachedFile(at url: URL) -> Bool {
        guard let fileSize = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return false }
        return fileSize > 0
    }
}
