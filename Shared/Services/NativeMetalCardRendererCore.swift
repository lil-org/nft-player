// ∅ 2026 lil org

import CoreGraphics
import Foundation
import ImageIO
import MetalKit
import os
import simd

enum NativeMetalCardLayout {
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

struct NativeMetalCardVertex {
    let position: SIMD2<Float>
    let uv: SIMD2<Float>
}

private struct NativeMetalCardVertexQuad {
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

struct NativeMetalCardUniforms {
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

struct NativeMetalCardInteractionState {
    let pointer: SIMD2<Float>
    let background: SIMD2<Float>
    let pointerFromCenter: Float
    let effectOpacity: Float
}

struct NativeMetalCardLoadedTextures {
    let face: MTLTexture
    let foil: MTLTexture
    let textureMask: MTLTexture
    let grain: MTLTexture
    let glitter: MTLTexture
    let rendersEffect: Bool
    let maskUsesAlpha: Bool
}

private struct NativeMetalCardImageTexture {
    let texture: MTLTexture
    let hasAlpha: Bool
}

private struct NativeMetalCardSharedTextureKey: Hashable {
    let path: String
    let generateMipmaps: Bool

    init(url: URL, generateMipmaps: Bool) {
        self.path = url.standardizedFileURL.path
        self.generateMipmaps = generateMipmaps
    }
}

private struct NativeMetalCardTextureLoadError: Error {
    let asset: NativeMetalCardAssetPath
    let underlyingError: Error
}

private struct NativeMetalCardLoadKey: Equatable {
    let tokenID: Int
    let renderKind: NativeMetalCardRenderKind
    let generation: UUID
}

final class NativeMetalCardRendererCore {

    var requestDraw: (() -> Void)?

    private var currentTokenID: Int?
    private var currentRenderKind: NativeMetalCardRenderKind?
    private var currentLoadKey: NativeMetalCardLoadKey?
    private var currentContentReadyLoadKey: NativeMetalCardLoadKey?
    private var currentContentReadyCallbacks = [() -> Void]()
    private(set) var metadata: NativeMetalCardMetadata?
    private(set) var textures: NativeMetalCardLoadedTextures?

    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private let placeholderTexture: MTLTexture
    private let textureQueue = DispatchQueue(label: "org.lil.nft-player.native-card-textures", qos: .userInitiated)
    private let textureLoader: MTKTextureLoader
    private let logger: Logger
    private var sharedTextureCache = [NativeMetalCardSharedTextureKey: MTLTexture]()

    init?(device: MTLDevice, logger: Logger) {
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
        self.textureLoader = MTKTextureLoader(device: device)
        self.logger = logger
    }

    func display(
        tokenID: Int,
        renderKind: NativeMetalCardRenderKind,
        onContentReady: (() -> Void)? = nil
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
        if currentRenderKind != renderKind {
            currentRenderKind?.cancelPrefetchDownloads()
        }
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
        let needsEffectAssets = tokenMetadata.requiresEffectAssets
        var loadedEffectAssets: NativeMetalCardAssetURLs?
        var loadedFaceTexture = previewFaceTexture
        let loadFullTexturesIfReady = { [weak self] in
            guard let self,
                  needsEffectAssets,
                  let assetURLs = loadedEffectAssets,
                  let faceTexture = loadedFaceTexture else {
                return
            }
            self.loadTextures(from: assetURLs, preloadedFace: faceTexture, loadKey: loadKey)
        }

        if needsEffectAssets {
            renderKind.loadEffectAssets(for: clampedTokenID) { [weak self] assetURLs in
                guard let self,
                      self.isCurrentLoad(loadKey) else {
                    return
                }
                guard let assetURLs else {
                    self.clearCurrentLoadIfCurrent(loadKey)
                    return
                }
                loadedEffectAssets = assetURLs
                loadFullTexturesIfReady()
            }
        }
        if previewFaceTexture == nil {
            renderKind.loadFace(for: clampedTokenID) { [weak self] faceURL in
                guard let self,
                      self.isCurrentLoad(loadKey) else {
                    return
                }
                guard let faceURL else {
                    self.clearCurrentLoadIfCurrent(loadKey)
                    return
                }
                self.loadFaceTexture(
                    from: faceURL,
                    tokenID: clampedTokenID,
                    renderKind: renderKind,
                    metadata: tokenMetadata,
                    loadKey: loadKey
                ) { faceTexture in
                    loadedFaceTexture = faceTexture
                    loadFullTexturesIfReady()
                }
            }
        } else {
            loadFullTexturesIfReady()
        }
        renderKind.prefetch(around: clampedTokenID, radius: 2)
    }

    func cancelPrefetchDownloads() {
        currentRenderKind?.cancelPrefetchDownloads()
    }

    func cancelContentReadyCallbacks() {
        currentContentReadyLoadKey = nil
        currentContentReadyCallbacks.removeAll()
    }

    func draw(
        in view: MTKView,
        cardRect: CGRect,
        cardScale: CGSize,
        interactionState: NativeMetalCardInteractionState
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

    private func loadFaceTexture(
        from url: URL,
        tokenID: Int,
        renderKind: NativeMetalCardRenderKind,
        metadata: NativeMetalCardMetadata,
        loadKey: NativeMetalCardLoadKey,
        completion: ((MTLTexture) -> Void)? = nil
    ) {
        textureQueue.async { [weak self] in
            guard let self else { return }

            do {
                let isCurrentLoad = {
                    self.isCurrentLoad(loadKey)
                }

                guard isCurrentLoad() else {
                    return
                }

                let faceTexture = try self.makeTexture(from: url)
                guard isCurrentLoad() else {
                    return
                }

                let loadedTextures = NativeMetalCardLoadedTextures(
                    face: faceTexture,
                    foil: self.placeholderTexture,
                    textureMask: self.placeholderTexture,
                    grain: self.placeholderTexture,
                    glitter: self.placeholderTexture,
                    rendersEffect: !metadata.requiresEffectAssets,
                    maskUsesAlpha: true
                )

                DispatchQueue.main.async { [weak self] in
                    guard let self,
                          self.isCurrentLoad(loadKey),
                          self.textures == nil else {
                        return
                    }

                    self.textures = loadedTextures
                    self.requestDraw?()
                    self.finishContentReadyCallbacksIfCurrent(loadKey)
                    if !metadata.requiresEffectAssets {
                        self.currentLoadKey = nil
                    }
                    completion?(faceTexture)
                }
            } catch {
                self.logger.error(
                    "Native card face texture load failed for \(renderKind.rawValue, privacy: .public) token \(tokenID, privacy: .public): \(String(describing: error), privacy: .public)"
                )
                renderKind.invalidateFaceAsset(for: tokenID)
                self.clearCurrentLoadIfCurrent(loadKey)
            }
        }
    }

    private func loadTextures(
        from assetURLs: NativeMetalCardAssetURLs,
        preloadedFace: MTLTexture,
        loadKey: NativeMetalCardLoadKey
    ) {
        textureQueue.async { [weak self] in
            guard let self else { return }

            do {
                let isCurrentLoad = {
                    self.isCurrentLoad(loadKey)
                }

                guard isCurrentLoad() else {
                    return
                }

                let maskTexture = try self.loadTexture(from: assetURLs.textureMask) { url in
                    try self.makeTextureWithAlphaInfo(from: url, generateMipmaps: true)
                }
                guard isCurrentLoad() else {
                    return
                }

                let foilTexture = try self.loadTexture(from: assetURLs.foil) { url in
                    try self.makeTexture(from: url, generateMipmaps: true)
                }
                guard isCurrentLoad() else {
                    return
                }

                let grainTexture = try self.loadTexture(from: assetURLs.grain) { url in
                    try self.makeSharedTexture(from: url, generateMipmaps: true)
                }
                guard isCurrentLoad() else {
                    return
                }

                let glitterTexture = try self.loadTexture(from: assetURLs.glitter) { url in
                    try self.makeSharedTexture(from: url, generateMipmaps: true)
                }
                guard isCurrentLoad() else {
                    return
                }

                let loadedTextures = NativeMetalCardLoadedTextures(
                    face: preloadedFace,
                    foil: foilTexture,
                    textureMask: maskTexture.texture,
                    grain: grainTexture,
                    glitter: glitterTexture,
                    rendersEffect: true,
                    maskUsesAlpha: maskTexture.hasAlpha
                )

                DispatchQueue.main.async { [weak self] in
                    guard let self,
                          self.isCurrentLoad(loadKey) else {
                        return
                    }

                    self.textures = loadedTextures
                    self.currentLoadKey = nil
                    self.requestDraw?()
                    self.finishContentReadyCallbacksIfCurrent(loadKey)
                }
            } catch {
                let textureLoadError = error as? NativeMetalCardTextureLoadError
                let loggedError = textureLoadError?.underlyingError ?? error
                self.logger.error(
                    "Native card effect texture load failed for \(assetURLs.renderKind.rawValue, privacy: .public) token \(assetURLs.tokenID, privacy: .public): \(String(describing: loggedError), privacy: .public)"
                )
                if let failedAsset = textureLoadError?.asset {
                    assetURLs.renderKind.invalidate(failedAsset)
                } else {
                    assetURLs.renderKind.invalidateEffectAssets(for: assetURLs.tokenID)
                }
                self.clearCurrentLoadIfCurrent(loadKey)
            }
        }
    }

    private func isCurrentLoad(_ loadKey: NativeMetalCardLoadKey) -> Bool {
        let isCurrent = {
            self.currentLoadKey == loadKey
        }

        if Thread.isMainThread {
            return isCurrent()
        }
        return DispatchQueue.main.sync(execute: isCurrent)
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
        let clear = {
            guard self.currentLoadKey == loadKey else {
                return
            }
            self.currentLoadKey = nil
            self.clearContentReadyCallbacksIfCurrent(loadKey)
        }

        if Thread.isMainThread {
            clear()
        } else {
            DispatchQueue.main.async(execute: clear)
        }
    }

    private func resetContentReadyCallbacks(
        for loadKey: NativeMetalCardLoadKey,
        callback: (() -> Void)?
    ) {
        currentContentReadyLoadKey = loadKey
        currentContentReadyCallbacks = callback.map { [$0] } ?? []
    }

    private func appendContentReadyCallback(
        _ callback: (() -> Void)?,
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

    private func notifyContentReady(_ callback: @escaping () -> Void) {
        DispatchQueue.main.async(execute: callback)
    }

    private func makeTextureWithAlphaInfo(
        from url: URL,
        generateMipmaps: Bool = false
    ) throws -> NativeMetalCardImageTexture {
        let image = try Self.image(at: url)
        let hasAlpha = Self.imageHasAlpha(image)
        return try NativeMetalCardImageTexture(
            texture: makeTexture(from: image, sourceName: url.lastPathComponent, generateMipmaps: generateMipmaps),
            hasAlpha: hasAlpha
        )
    }

    private func makeTexture(from url: URL, generateMipmaps: Bool = false) throws -> MTLTexture {
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
            throw NativeMetalCardTextureLoadError(asset: assetURL.asset, underlyingError: error)
        }
    }

    private func makeSharedTexture(from url: URL, generateMipmaps: Bool = false) throws -> MTLTexture {
        let key = NativeMetalCardSharedTextureKey(url: url, generateMipmaps: generateMipmaps)
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
                return try makeTexture(from: normalizedImage, generateMipmaps: generateMipmaps)
            } catch {
                logger.error(
                    "Native card texture normalization failed for \(sourceName, privacy: .public): \(String(describing: error), privacy: .public)"
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

    private static func imageHasAlpha(_ image: CGImage) -> Bool {
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
