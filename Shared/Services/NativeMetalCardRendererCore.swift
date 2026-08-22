// ∅ 2026 lil org

import CoreGraphics
import Foundation
import ImageIO
import MetalKit
import os
import simd

nonisolated enum NativeMetalCardLayout {
    static let cardAspectRatio = CGFloat(1000.0 / 1400.0)
    static let cardViewportInset = CGFloat(23)
    static let cardCornerRadiusScale = CGSize(width: 0.0455, height: 0.035)

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

    static func cardCornerRadii(in size: CGSize) -> CGSize {
        CGSize(
            width: size.width * cardCornerRadiusScale.width,
            height: size.height * cardCornerRadiusScale.height
        )
    }
}

nonisolated struct NativeMetalCardVertex: Sendable {
    let position: SIMD2<Float>
    let uv: SIMD2<Float>
}

private nonisolated struct NativeMetalCardVertexQuad: Sendable {
    static let vertexCount = 4

    var topLeft: NativeMetalCardVertex
    var bottomLeft: NativeMetalCardVertex
    var topRight: NativeMetalCardVertex
    var bottomRight: NativeMetalCardVertex

    static func cardVertices(in size: CGSize, cardRect: CGRect) -> NativeMetalCardVertexQuad? {
        guard size.width > 0, size.height > 0, !cardRect.isEmpty else { return nil }

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

        return NativeMetalCardVertexQuad(
            topLeft: NativeMetalCardVertex(position: ndc(minX, minY), uv: SIMD2<Float>(0, 0)),
            bottomLeft: NativeMetalCardVertex(position: ndc(minX, maxY), uv: SIMD2<Float>(0, 1)),
            topRight: NativeMetalCardVertex(position: ndc(maxX, minY), uv: SIMD2<Float>(1, 0)),
            bottomRight: NativeMetalCardVertex(position: ndc(maxX, maxY), uv: SIMD2<Float>(1, 1))
        )
    }
}

nonisolated struct NativeMetalCardUniforms: Sendable {
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

nonisolated struct NativeMetalCardInteractionState: Sendable {
    let pointer: SIMD2<Float>
    let background: SIMD2<Float>
    let pointerFromCenter: Float
    let effectOpacity: Float
}

@MainActor struct NativeMetalCardLoadedTextures {
    let face: MTLTexture
    let foil: MTLTexture
    let textureMask: MTLTexture
    let grain: MTLTexture
    let glitter: MTLTexture
    let rendersEffect: Bool
    let maskUsesAlpha: Bool
}

private nonisolated struct NativeMetalCardImageTexture {
    let texture: MTLTexture
    let hasAlpha: Bool
}

private nonisolated struct NativeMetalCardTextureTransfer: @unchecked Sendable {
    let texture: MTLTexture
}

private nonisolated struct NativeMetalCardTextureBundleTransfer: @unchecked Sendable {
    let face: MTLTexture
    let foil: MTLTexture
    let textureMask: MTLTexture
    let grain: MTLTexture
    let glitter: MTLTexture
    let maskUsesAlpha: Bool
}

private nonisolated struct NativeMetalCardSharedTextureKey: Hashable, Sendable {
    let path: String
    let generateMipmaps: Bool

    init(url: URL, generateMipmaps: Bool) {
        self.path = url.standardizedFileURL.path
        self.generateMipmaps = generateMipmaps
    }
}

private nonisolated struct NativeMetalCardTextureLoadError: Error, Sendable {
    let assetURL: NativeMetalCardAssetURL
    let underlyingError: Error
}

private nonisolated struct NativeMetalCardLoadKey: Equatable, Sendable {
    let tokenID: Int
    let renderKind: NativeMetalCardRenderKind
    let generation: UUID
}

nonisolated struct NativeMetalCardRendererAssetLoader: Sendable {
    let loadFace: @Sendable (NativeMetalCardRenderKind, Int) async -> NativeMetalCardAssetURL?
    let loadEffectAssets: @Sendable (NativeMetalCardRenderKind, Int) async -> NativeMetalCardAssetURLs?
    let prefetch: @Sendable (NativeMetalCardRenderKind, Int, Int) async -> Void
    let cancelPrefetchDownloads: @Sendable (NativeMetalCardRenderKind) async -> Void
    let invalidateAsset: @Sendable (NativeMetalCardRenderKind, NativeMetalCardAssetURL) async -> Void

    static let live = NativeMetalCardRendererAssetLoader(
        loadFace: { renderKind, tokenID in
            await renderKind.loadFace(for: tokenID)
        },
        loadEffectAssets: { renderKind, tokenID in
            await renderKind.loadEffectAssets(for: tokenID)
        },
        prefetch: { renderKind, tokenID, radius in
            await renderKind.prefetch(around: tokenID, radius: radius)
        },
        cancelPrefetchDownloads: { renderKind in
            await renderKind.cancelPrefetchDownloads()
        },
        invalidateAsset: { renderKind, assetURL in
            await renderKind.invalidate(assetURL)
        }
    )
}

private actor NativeMetalCardTextureWorker {
    private let textureLoader: MTKTextureLoader
    private let logger: Logger
    private var sharedTextureCache = [NativeMetalCardSharedTextureKey: MTLTexture]()

    init(device: MTLDevice, logger: Logger) {
        textureLoader = MTKTextureLoader(device: device)
        self.logger = logger
    }

    func loadFace(from assetURL: NativeMetalCardAssetURL) throws -> NativeMetalCardTextureTransfer {
        try Task.checkCancellation()
        return NativeMetalCardTextureTransfer(
            texture: try loadTexture(from: assetURL) { url in
                try makeTexture(from: url)
            }
        )
    }

    func loadTextures(
        from assetURLs: NativeMetalCardAssetURLs,
        face: NativeMetalCardTextureTransfer
    ) throws -> NativeMetalCardTextureBundleTransfer {
        try Task.checkCancellation()
        let maskTexture = try loadTexture(from: assetURLs.textureMask) { url in
            try makeTextureWithAlphaInfo(from: url, generateMipmaps: true)
        }
        try Task.checkCancellation()
        let foilTexture = try loadTexture(from: assetURLs.foil) { url in
            try makeTexture(from: url, generateMipmaps: true)
        }
        try Task.checkCancellation()
        let grainTexture = try loadTexture(from: assetURLs.grain) { url in
            try makeSharedTexture(from: url, generateMipmaps: true)
        }
        try Task.checkCancellation()
        let glitterTexture = try loadTexture(from: assetURLs.glitter) { url in
            try makeSharedTexture(from: url, generateMipmaps: true)
        }
        try Task.checkCancellation()

        return NativeMetalCardTextureBundleTransfer(
            face: face.texture,
            foil: foilTexture,
            textureMask: maskTexture.texture,
            grain: grainTexture,
            glitter: glitterTexture,
            maskUsesAlpha: maskTexture.hasAlpha
        )
    }

    private func makeTextureWithAlphaInfo(
        from url: URL,
        generateMipmaps: Bool = false
    ) throws -> NativeMetalCardImageTexture {
        let image = try Self.image(at: url)
        let hasAlpha = Self.imageHasAlpha(image)
        return try NativeMetalCardImageTexture(
            texture: makeTexture(
                from: image,
                sourceName: url.lastPathComponent,
                generateMipmaps: generateMipmaps
            ),
            hasAlpha: hasAlpha
        )
    }

    private func makeTexture(
        from url: URL,
        generateMipmaps: Bool = false
    ) throws -> MTLTexture {
        try makeTexture(
            from: Self.image(at: url),
            sourceName: url.lastPathComponent,
            generateMipmaps: generateMipmaps
        )
    }

    private func loadTexture<T>(
        from assetURL: NativeMetalCardAssetURL,
        _ load: (URL) throws -> T
    ) throws -> T {
        do {
            return try load(assetURL.url)
        } catch {
            throw NativeMetalCardTextureLoadError(
                assetURL: assetURL,
                underlyingError: error
            )
        }
    }

    private func makeSharedTexture(
        from url: URL,
        generateMipmaps: Bool = false
    ) throws -> MTLTexture {
        let key = NativeMetalCardSharedTextureKey(
            url: url,
            generateMipmaps: generateMipmaps
        )
        if let texture = sharedTextureCache[key] {
            return texture
        }

        let texture = try makeTexture(from: url, generateMipmaps: generateMipmaps)
        sharedTextureCache[key] = texture
        return texture
    }

    private static func image(at url: URL) throws -> CGImage {
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return image
    }

    private func makeTexture(
        from image: CGImage,
        sourceName: String,
        generateMipmaps: Bool = false
    ) throws -> MTLTexture {
        do {
            return try makeTexture(from: image, generateMipmaps: generateMipmaps)
        } catch {
            let originalError = error
            guard let normalizedImage = Self.normalizedImage(from: image) else {
                throw originalError
            }

            do {
                return try makeTexture(
                    from: normalizedImage,
                    generateMipmaps: generateMipmaps
                )
            } catch {
                logger.error(
                    "Native card texture normalization failed for \(sourceName, privacy: .public): \(String(describing: error), privacy: .public)"
                )
                throw originalError
            }
        }
    }

    private func makeTexture(
        from image: CGImage,
        generateMipmaps: Bool = false
    ) throws -> MTLTexture {
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

        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue
            | CGImageAlphaInfo.premultipliedLast.rawValue
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

    private static func imageHasAlpha(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast:
            return false
        default:
            return true
        }
    }
}

@MainActor final class NativeMetalCardRendererCore {

    var requestDraw: (@MainActor () -> Void)?

    private struct PendingContentLoad {
        let loadKey: NativeMetalCardLoadKey
        var faceTexture: NativeMetalCardTextureTransfer?
        var effectAssetURLs: NativeMetalCardAssetURLs?
        var effectAssetLoadFailed: Bool
    }

    private var currentTokenID: Int?
    private var currentRenderKind: NativeMetalCardRenderKind?
    private var currentLoadKey: NativeMetalCardLoadKey?
    private var currentContentReadyLoadKey: NativeMetalCardLoadKey?
    private var currentContentReadyCallbacks = [@MainActor () -> Void]()
    private var pendingContentLoad: PendingContentLoad?
    private var faceAssetTask: Task<Void, Never>?
    private var effectAssetTask: Task<Void, Never>?
    private var textureLoadTask: Task<Void, Never>?
    private var prefetchTask: Task<Void, Never>?
    private var prefetchCancellationTasks = [NativeMetalCardRenderKind: Task<Void, Never>]()
    private(set) var metadata: NativeMetalCardMetadata?
    private(set) var textures: NativeMetalCardLoadedTextures?

    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private let placeholderTexture: MTLTexture
    private let textureWorker: NativeMetalCardTextureWorker
    private let assetLoader: NativeMetalCardRendererAssetLoader
    private let logger: Logger

    init?(
        device: MTLDevice,
        logger: Logger,
        assetLoader: NativeMetalCardRendererAssetLoader = .live
    ) {
        guard let commandQueue = device.makeCommandQueue() else {
            logger.error("Metal command queue creation failed")
            return nil
        }
        guard let placeholderTexture = Self.makeSolidTexture(device: device, red: 0, green: 0, blue: 0, alpha: 255) else {
            logger.error("Metal placeholder texture creation failed")
            return nil
        }
        guard let library = device.makeDefaultLibrary() else {
            logger.error("Default Metal library is unavailable; check that PonchoDrifellaShaders.metal is in the target sources")
            return nil
        }
        guard let vertexFunction = library.makeFunction(name: "nativeMetalCardVertex"),
              let fragmentFunction = library.makeFunction(name: "nativeMetalCardFragment") else {
            logger.error("Native Metal card shader functions are missing from the default library")
            return nil
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

        let pipelineState: MTLRenderPipelineState
        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            logger.error("Native Metal card pipeline creation failed: \(String(describing: error), privacy: .public)")
            return nil
        }

        self.commandQueue = commandQueue
        self.pipelineState = pipelineState
        self.placeholderTexture = placeholderTexture
        self.textureWorker = NativeMetalCardTextureWorker(
            device: device,
            logger: logger
        )
        self.assetLoader = assetLoader
        self.logger = logger
    }

    func display(
        tokenID: Int,
        renderKind: NativeMetalCardRenderKind,
        onContentReady: (@MainActor () -> Void)? = nil
    ) {
        let clampedTokenID = min(max(tokenID, 1), renderKind.tokenCount)
        let tokenMetadata = renderKind.metadata(for: clampedTokenID)
        let isSameToken = currentTokenID == clampedTokenID && currentRenderKind == renderKind
        if isSameToken,
           let textures {
            if let onContentReady {
                notifyContentReady(onContentReady)
            }
            if !tokenMetadata.requiresEffectAssets || textures.rendersEffect {
                return
            }
            if activeLoadKey(tokenID: clampedTokenID, renderKind: renderKind) != nil {
                return
            }
        }
        if isSameToken,
           let loadKey = activeLoadKey(tokenID: clampedTokenID, renderKind: renderKind) {
            appendContentReadyCallback(onContentReady, for: loadKey)
            return
        }

        let previewFaceTexture = isSameToken && textures?.rendersEffect == false ? textures?.face : nil
        let previousRenderKind = currentRenderKind != renderKind
            ? currentRenderKind
            : nil
        cancelCurrentContentLoadTasks()
        prefetchTask?.cancel()
        schedulePrefetchCancellation(for: previousRenderKind)
        let pendingCancellationTask = prefetchCancellationTasks[renderKind]
        currentTokenID = clampedTokenID
        currentRenderKind = renderKind
        metadata = tokenMetadata
        if previewFaceTexture == nil {
            textures = nil
        }

        let generation = UUID()
        let loadKey = NativeMetalCardLoadKey(
            tokenID: clampedTokenID,
            renderKind: renderKind,
            generation: generation
        )
        currentLoadKey = loadKey
        resetContentReadyCallbacks(for: loadKey, callback: previewFaceTexture == nil ? onContentReady : nil)
        pendingContentLoad = PendingContentLoad(
            loadKey: loadKey,
            faceTexture: previewFaceTexture.map {
                NativeMetalCardTextureTransfer(texture: $0)
            },
            effectAssetURLs: nil,
            effectAssetLoadFailed: false
        )
        if previewFaceTexture == nil {
            startFaceAssetLoad(
                tokenID: clampedTokenID,
                renderKind: renderKind,
                metadata: tokenMetadata,
                loadKey: loadKey
            )
        }
        if tokenMetadata.requiresEffectAssets {
            startEffectAssetLoad(
                tokenID: clampedTokenID,
                renderKind: renderKind,
                loadKey: loadKey
            )
        }
        let assetLoader = self.assetLoader
        prefetchTask = Task {
            guard !Task.isCancelled else { return }
            await pendingCancellationTask?.value
            guard !Task.isCancelled else { return }
            await assetLoader.prefetch(renderKind, clampedTokenID, 2)
        }
    }

    func cancelPrefetchDownloads() {
        prefetchTask?.cancel()
        prefetchTask = nil
        schedulePrefetchCancellation(for: currentRenderKind)
    }

    private func schedulePrefetchCancellation(
        for renderKind: NativeMetalCardRenderKind?
    ) {
        guard let renderKind else { return }
        let previousTask = prefetchCancellationTasks[renderKind]
        let assetLoader = self.assetLoader
        prefetchCancellationTasks[renderKind] = Task {
            await previousTask?.value
            await assetLoader.cancelPrefetchDownloads(renderKind)
        }
    }

    func cancelContentReadyCallbacks() {
        currentContentReadyLoadKey = nil
        currentContentReadyCallbacks.removeAll()
    }

    func draw(
        in view: MTKView,
        cardRect: CGRect,
        cardScale: CGSize,
        interactionState: NativeMetalCardInteractionState,
        onContentFramePresented: (@MainActor @Sendable () -> Void)? = nil
    ) {
        guard var vertices = NativeMetalCardVertexQuad.cardVertices(in: view.bounds.size, cardRect: cardRect) else {
            return
        }

        guard let renderPassDescriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            return
        }

        guard let textures,
              let metadata else {
            clearAndPresent(
                renderPassDescriptor: renderPassDescriptor,
                drawable: drawable,
                commandBuffer: commandBuffer,
                clearColor: view.clearColor
            )
            return
        }

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }

        var uniforms = NativeMetalCardUniforms(
            pointer: interactionState.pointer,
            background: interactionState.background,
            cardSize: SIMD2<Float>(
                Float(cardRect.width * cardScale.width),
                Float(cardRect.height * cardScale.height)
            ),
            pointerFromCenter: interactionState.pointerFromCenter,
            opacity: textures.rendersEffect ? interactionState.effectOpacity : 0,
            maskUsesAlpha: textures.maskUsesAlpha ? 1 : 0,
            effectKind: Int32(metadata.effectKind),
            glowKind: Int32(metadata.glowKind)
        )

        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBytes(
            &vertices,
            length: MemoryLayout<NativeMetalCardVertexQuad>.stride,
            index: 0
        )
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<NativeMetalCardUniforms>.stride, index: 0)
        encoder.setFragmentTexture(textures.face, index: 0)
        encoder.setFragmentTexture(textures.foil, index: 1)
        encoder.setFragmentTexture(textures.textureMask, index: 2)
        encoder.setFragmentTexture(textures.grain, index: 3)
        encoder.setFragmentTexture(textures.glitter, index: 4)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: NativeMetalCardVertexQuad.vertexCount)
        encoder.endEncoding()

        if let onContentFramePresented {
            commandBuffer.addCompletedHandler { completedCommandBuffer in
                guard completedCommandBuffer.status == .completed else { return }
                Task { @MainActor in
                    onContentFramePresented()
                }
            }
        }
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private func clearAndPresent(
        renderPassDescriptor: MTLRenderPassDescriptor,
        drawable: MTLDrawable,
        commandBuffer: MTLCommandBuffer,
        clearColor: MTLClearColor
    ) {
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].clearColor = clearColor
        renderPassDescriptor.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }

        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private func startFaceAssetLoad(
        tokenID: Int,
        renderKind: NativeMetalCardRenderKind,
        metadata: NativeMetalCardMetadata,
        loadKey: NativeMetalCardLoadKey
    ) {
        let assetLoader = self.assetLoader
        faceAssetTask = Task { [weak self] in
            let faceAssetURL = await assetLoader.loadFace(renderKind, tokenID)
            guard !Task.isCancelled else { return }
            guard let faceAssetURL else {
                self?.clearCurrentLoadIfCurrent(loadKey)
                return
            }
            await self?.loadFaceTexture(
                from: faceAssetURL,
                tokenID: tokenID,
                renderKind: renderKind,
                metadata: metadata,
                loadKey: loadKey
            )
        }
    }

    private func startEffectAssetLoad(
        tokenID: Int,
        renderKind: NativeMetalCardRenderKind,
        loadKey: NativeMetalCardLoadKey
    ) {
        let assetLoader = self.assetLoader
        effectAssetTask = Task { [weak self] in
            let assetURLs = await assetLoader.loadEffectAssets(renderKind, tokenID)
            guard !Task.isCancelled else { return }
            guard let assetURLs else {
                self?.receiveEffectAssetLoadFailure(loadKey: loadKey)
                return
            }
            self?.receiveEffectAssetURLs(assetURLs, loadKey: loadKey)
        }
    }

    private func loadFaceTexture(
        from faceAssetURL: NativeMetalCardAssetURL,
        tokenID: Int,
        renderKind: NativeMetalCardRenderKind,
        metadata: NativeMetalCardMetadata,
        loadKey: NativeMetalCardLoadKey
    ) async {
        guard isCurrentLoad(loadKey), !Task.isCancelled else { return }
        do {
            let faceTexture = try await textureWorker.loadFace(from: faceAssetURL)
            guard isCurrentLoad(loadKey), !Task.isCancelled,
                  var pendingContentLoad,
                  pendingContentLoad.loadKey == loadKey else {
                return
            }
            faceAssetTask = nil
            pendingContentLoad.faceTexture = faceTexture
            self.pendingContentLoad = pendingContentLoad
            if textures == nil {
                textures = NativeMetalCardLoadedTextures(
                    face: faceTexture.texture,
                    foil: placeholderTexture,
                    textureMask: placeholderTexture,
                    grain: placeholderTexture,
                    glitter: placeholderTexture,
                    rendersEffect: !metadata.requiresEffectAssets,
                    maskUsesAlpha: true
                )
                requestDraw?()
                finishContentReadyCallbacksIfCurrent(loadKey)
            }
            guard metadata.requiresEffectAssets else {
                currentLoadKey = nil
                self.pendingContentLoad = nil
                return
            }
            startFullTextureLoadIfReady(loadKey: loadKey)
        } catch is CancellationError {
            return
        } catch {
            guard isCurrentLoad(loadKey), !Task.isCancelled else { return }
            let textureLoadError = error as? NativeMetalCardTextureLoadError
            let loggedError = textureLoadError?.underlyingError ?? error
            logger.error(
                "Native card face texture load failed for \(renderKind.rawValue, privacy: .public) token \(tokenID, privacy: .public): \(String(describing: loggedError), privacy: .public)"
            )
            if let failedAssetURL = textureLoadError?.assetURL {
                await assetLoader.invalidateAsset(renderKind, failedAssetURL)
            }
            clearCurrentLoadIfCurrent(loadKey)
        }
    }

    private func receiveEffectAssetURLs(
        _ assetURLs: NativeMetalCardAssetURLs,
        loadKey: NativeMetalCardLoadKey
    ) {
        guard isCurrentLoad(loadKey),
              var pendingContentLoad,
              pendingContentLoad.loadKey == loadKey else {
            return
        }
        effectAssetTask = nil
        pendingContentLoad.effectAssetURLs = assetURLs
        self.pendingContentLoad = pendingContentLoad
        startFullTextureLoadIfReady(loadKey: loadKey)
    }

    private func receiveEffectAssetLoadFailure(loadKey: NativeMetalCardLoadKey) {
        guard isCurrentLoad(loadKey),
              var pendingContentLoad,
              pendingContentLoad.loadKey == loadKey else {
            return
        }
        effectAssetTask = nil
        pendingContentLoad.effectAssetLoadFailed = true
        self.pendingContentLoad = pendingContentLoad
        finishEffectAssetLoadFailureIfReady(loadKey: loadKey)
    }

    private func finishEffectAssetLoadFailureIfReady(loadKey: NativeMetalCardLoadKey) {
        guard isCurrentLoad(loadKey),
              let pendingContentLoad,
              pendingContentLoad.loadKey == loadKey,
              pendingContentLoad.effectAssetLoadFailed,
              pendingContentLoad.faceTexture != nil else {
            return
        }
        currentLoadKey = nil
        self.pendingContentLoad = nil
        clearContentReadyCallbacksIfCurrent(loadKey)
    }

    private func startFullTextureLoadIfReady(loadKey: NativeMetalCardLoadKey) {
        guard let pendingContentLoad,
              pendingContentLoad.loadKey == loadKey else {
            return
        }
        if pendingContentLoad.effectAssetLoadFailed {
            finishEffectAssetLoadFailureIfReady(loadKey: loadKey)
            return
        }
        guard textureLoadTask == nil,
              let faceTexture = pendingContentLoad.faceTexture,
              let assetURLs = pendingContentLoad.effectAssetURLs else {
            return
        }

        let textureWorker = self.textureWorker
        let assetLoader = self.assetLoader
        let logger = self.logger
        textureLoadTask = Task { [weak self] in
            do {
                let loadedTextures = try await textureWorker.loadTextures(
                    from: assetURLs,
                    face: faceTexture
                )
                guard !Task.isCancelled else { return }
                self?.finishFullTextureLoad(loadedTextures, loadKey: loadKey)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled,
                      self?.isCurrentLoad(loadKey) == true else {
                    return
                }
                let textureLoadError = error as? NativeMetalCardTextureLoadError
                let loggedError = textureLoadError?.underlyingError ?? error
                logger.error(
                    "Native card effect texture load failed for \(assetURLs.renderKind.rawValue, privacy: .public) token \(assetURLs.tokenID, privacy: .public): \(String(describing: loggedError), privacy: .public)"
                )
                if let failedAssetURL = textureLoadError?.assetURL {
                    await assetLoader.invalidateAsset(assetURLs.renderKind, failedAssetURL)
                } else {
                    await assetLoader.invalidateAsset(assetURLs.renderKind, assetURLs.foil)
                    await assetLoader.invalidateAsset(assetURLs.renderKind, assetURLs.textureMask)
                }
                self?.clearCurrentLoadIfCurrent(loadKey)
            }
        }
    }

    private func finishFullTextureLoad(
        _ loadedTextures: NativeMetalCardTextureBundleTransfer,
        loadKey: NativeMetalCardLoadKey
    ) {
        guard isCurrentLoad(loadKey) else { return }
        textureLoadTask = nil
        pendingContentLoad = nil
        textures = NativeMetalCardLoadedTextures(
            face: loadedTextures.face,
            foil: loadedTextures.foil,
            textureMask: loadedTextures.textureMask,
            grain: loadedTextures.grain,
            glitter: loadedTextures.glitter,
            rendersEffect: true,
            maskUsesAlpha: loadedTextures.maskUsesAlpha
        )
        currentLoadKey = nil
        requestDraw?()
        finishContentReadyCallbacksIfCurrent(loadKey)
    }

    private func cancelCurrentContentLoadTasks() {
        faceAssetTask?.cancel()
        faceAssetTask = nil
        effectAssetTask?.cancel()
        effectAssetTask = nil
        textureLoadTask?.cancel()
        textureLoadTask = nil
        pendingContentLoad = nil
    }

    private func isCurrentLoad(_ loadKey: NativeMetalCardLoadKey) -> Bool {
        currentLoadKey == loadKey
    }

    private func activeLoadKey(
        tokenID: Int,
        renderKind: NativeMetalCardRenderKind
    ) -> NativeMetalCardLoadKey? {
        guard let currentLoadKey,
              currentLoadKey.tokenID == tokenID,
              currentLoadKey.renderKind == renderKind else {
            return nil
        }
        return currentLoadKey
    }

    private func clearCurrentLoadIfCurrent(_ loadKey: NativeMetalCardLoadKey) {
        guard currentLoadKey == loadKey else { return }
        currentLoadKey = nil
        cancelCurrentContentLoadTasks()
        clearContentReadyCallbacksIfCurrent(loadKey)
    }

    private func resetContentReadyCallbacks(
        for loadKey: NativeMetalCardLoadKey,
        callback: (@MainActor () -> Void)?
    ) {
        currentContentReadyLoadKey = loadKey
        currentContentReadyCallbacks = callback.map { [$0] } ?? []
    }

    private func appendContentReadyCallback(
        _ callback: (@MainActor () -> Void)?,
        for loadKey: NativeMetalCardLoadKey
    ) {
        guard let callback else { return }
        guard currentContentReadyLoadKey == loadKey else {
            resetContentReadyCallbacks(for: loadKey, callback: callback)
            return
        }
        currentContentReadyCallbacks.append(callback)
    }

    private func finishContentReadyCallbacksIfCurrent(_ loadKey: NativeMetalCardLoadKey) {
        guard currentContentReadyLoadKey == loadKey else { return }

        let callbacks = currentContentReadyCallbacks
        clearContentReadyCallbacksIfCurrent(loadKey)
        callbacks.forEach { notifyContentReady($0) }
    }

    private func clearContentReadyCallbacksIfCurrent(_ loadKey: NativeMetalCardLoadKey) {
        guard currentContentReadyLoadKey == loadKey else { return }

        currentContentReadyLoadKey = nil
        currentContentReadyCallbacks.removeAll()
    }

    private func notifyContentReady(_ callback: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            callback()
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
