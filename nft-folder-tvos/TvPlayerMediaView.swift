// ∅ 2026 lil org

import Foundation
import SwiftUI
import UIKit

struct TvPlayerMediaView: View {

    private static let htmlDocumentRenderQueue = DispatchQueue(
        label: "org.lil.nft-folder.tvos-html-document-render",
        qos: .userInitiated
    )

    let token: GeneratedToken
    let context: PlayerTokenContext?
    let preferredPrefetchDirection: DownloadableMediaCache.PrefetchDirection

    @State private var ownerId = UUID()
    @State private var staticImage: UIImage?
    @State private var staticImageDescriptor: CollectionCatalogDownloadableMediaDescriptor?
    @State private var localWebContent: TvWebContent?
    @State private var localWebContentDescriptor: CollectionCatalogDownloadableMediaDescriptor?
    @State private var fallbackHTMLDescriptor: CollectionCatalogDownloadableMediaDescriptor?
    @State private var pendingHTMLDocumentRender: TvHTMLDocumentRenderRequest?
    @State private var cancelActiveLoad: (() -> Void)?

    var body: some View {
        content
            .onAppear(perform: renderCurrentContent)
            .onChange(of: renderKey) { _ in
                renderCurrentContent()
            }
            .onReceive(NotificationCenter.default.publisher(for: .downloadableMediaCacheFileAvailabilityDidChange)) { _ in
                renderAvailableContent()
            }
            .onDisappear(perform: cleanup)
    }

    @ViewBuilder
    private var content: some View {
        if let descriptor = downloadableMediaDescriptor {
            if descriptor.isStaticImage,
               staticImageDescriptor == descriptor,
               let staticImage {
                Image(uiImage: staticImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
            } else if !descriptor.isStaticImage,
                      localWebContentDescriptor == descriptor,
                      let localWebContent {
                TvGeneratedTokenView(
                    webContent: localWebContent,
                    fallbackURL: fallbackURL(for: token, descriptor: descriptor),
                    onLocalLoadFailure: {
                        handleLocalWebContentLoadFailure(for: descriptor)
                    }
                )
            } else if fallbackHTMLDescriptor == descriptor {
                TvGeneratedTokenView(
                    contentString: token.html,
                    fallbackURL: fallbackURL(for: token, descriptor: descriptor)
                )
            } else {
                Color.black
            }
        } else {
            TvGeneratedTokenView(contentString: token.html, fallbackURL: fallbackURL(for: token))
        }
    }

    private var renderKey: TvPlayerRenderKey {
        TvPlayerRenderKey(
            collectionId: context?.collectionId ?? token.fullCollectionId,
            tokenId: token.id,
            context: context,
            media: token.media,
            preferredPrefetchDirection: preferredPrefetchDirection
        )
    }

    private var downloadableMediaDescriptor: CollectionCatalogDownloadableMediaDescriptor? {
        CollectionCatalog.downloadableMediaDescriptor(for: context)
    }

    private func renderCurrentContent() {
        renderCurrentContent(shouldPrepareWindow: true)
    }

    private func renderAvailableContent() {
        renderCurrentContent(shouldPrepareWindow: false)
    }

    private func renderCurrentContent(shouldPrepareWindow: Bool) {
        let descriptor = shouldPrepareWindow
            ? prepareCurrentDownloadableMediaWindow()
            : downloadableMediaDescriptor

        guard let descriptor else {
            cleanup()
            return
        }

        if descriptor.isStaticImage {
            renderStaticImage(descriptor)
        } else {
            renderLocalWebMedia(descriptor)
        }
    }

    private func prepareCurrentDownloadableMediaWindow() -> CollectionCatalogDownloadableMediaDescriptor? {
        let cache = DownloadableMediaCache.shared
        guard let descriptor = cache.prepareWindow(
            for: context,
            ownerId: ownerId,
            direction: preferredPrefetchDirection
        ) else {
            cache.clearActiveWindow(ownerId: ownerId)
            return nil
        }

        return descriptor
    }

    private func renderStaticImage(_ descriptor: CollectionCatalogDownloadableMediaDescriptor) {
        guard staticImageDescriptor != descriptor || staticImage == nil else { return }

        localWebContent = nil
        localWebContentDescriptor = nil
        pendingHTMLDocumentRender = nil

        if staticImageDescriptor != descriptor {
            cancelActiveLoadIfNeeded()
            staticImage = nil
            staticImageDescriptor = descriptor
            clearDownloadableMediaFallback()
        }

        if let cachedImage = DownloadableMediaCache.shared.cachedDecodedImage(for: descriptor) {
            cancelActiveLoadIfNeeded()
            clearDownloadableMediaFallback()
            staticImage = cachedImage
            staticImageDescriptor = descriptor
            return
        }

        guard cancelActiveLoad == nil else { return }

        cancelActiveLoad = DownloadableMediaCache.shared.loadImage(for: descriptor) { image in
            cancelActiveLoad = nil
            guard staticImageDescriptor == descriptor else {
                return
            }
            guard let image else {
                renderDownloadableMediaFallback(for: descriptor)
                return
            }

            clearDownloadableMediaFallback()
            staticImage = image
        }
    }

    private func renderLocalWebMedia(_ descriptor: CollectionCatalogDownloadableMediaDescriptor) {
        staticImage = nil
        staticImageDescriptor = nil

        if localWebContentDescriptor == descriptor,
           localWebContent != nil {
            return
        }

        if localWebContentDescriptor != descriptor {
            cancelActiveLoadIfNeeded()
            localWebContent = nil
            localWebContentDescriptor = descriptor
            pendingHTMLDocumentRender = nil
            clearDownloadableMediaFallback()
        }

        let cache = DownloadableMediaCache.shared
        guard let localFileURL = cache.localFileURL(for: descriptor) else {
            guard cancelActiveLoad == nil else { return }
            cancelActiveLoad = cache.loadFile(for: descriptor) { fileURL in
                cancelActiveLoad = nil
                guard localWebContentDescriptor == descriptor else {
                    return
                }
                guard let fileURL else {
                    renderDownloadableMediaFallback(for: descriptor)
                    return
                }

                setLocalWebContent(
                    for: descriptor,
                    fileURL: fileURL,
                    nextLocalFileURL: adjacentLocalFileURL(for: descriptor)
                )
            }
            return
        }

        if pendingHTMLDocumentRender == TvHTMLDocumentRenderRequest(
            descriptor: descriptor,
            fileURL: localFileURL
        ) {
            return
        }

        cancelActiveLoadIfNeeded()
        setLocalWebContent(
            for: descriptor,
            fileURL: localFileURL,
            nextLocalFileURL: adjacentLocalFileURL(for: descriptor)
        )
    }

    private func setLocalWebContent(
        for descriptor: CollectionCatalogDownloadableMediaDescriptor,
        fileURL: URL,
        nextLocalFileURL: URL?
    ) {
        if case .html = descriptor.media {
            renderLocalHTMLDocument(for: descriptor, fileURL: fileURL)
            return
        }

        pendingHTMLDocumentRender = nil
        guard let content = localWebContent(
            for: descriptor,
            fileURL: fileURL,
            nextLocalFileURL: nextLocalFileURL
        ) else {
            localWebContent = nil
            renderDownloadableMediaFallback(for: descriptor)
            return
        }

        clearDownloadableMediaFallback()
        localWebContentDescriptor = descriptor
        localWebContent = content
    }

    private func renderLocalHTMLDocument(
        for descriptor: CollectionCatalogDownloadableMediaDescriptor,
        fileURL: URL
    ) {
        let request = TvHTMLDocumentRenderRequest(descriptor: descriptor, fileURL: fileURL)
        guard pendingHTMLDocumentRender != request else { return }

        pendingHTMLDocumentRender = request
        localWebContent = nil
        clearDownloadableMediaFallback()

        Self.htmlDocumentRenderQueue.async {
            let baseURL = DownloadableMediaCache.shared.downloadedSourceURL(for: descriptor).absoluteString
            let renderedContent = (try? String(contentsOf: fileURL, encoding: .utf8)).map { documentHTML in
                DownloadableTokenHTML.createInlineHTMLDocumentHTML(
                    documentHTML: documentHTML,
                    baseURL: baseURL,
                    contentSize: DownloadableTokenHTMLLayout.rootSVGViewBoxSize(in: documentHTML)
                )
            }

            DispatchQueue.main.async {
                guard pendingHTMLDocumentRender == request,
                      localWebContentDescriptor == descriptor else {
                    return
                }

                pendingHTMLDocumentRender = nil
                guard let renderedContent else {
                    localWebContent = nil
                    renderDownloadableMediaFallback(for: descriptor)
                    return
                }

                clearDownloadableMediaFallback()
                localWebContent = .localHTML(
                    string: renderedContent,
                    directoryURL: DownloadableMediaCache.shared.webViewHTMLDirectoryURL
                )
            }
        }
    }

    private func localWebContent(
        for descriptor: CollectionCatalogDownloadableMediaDescriptor,
        fileURL: URL,
        nextLocalFileURL: URL?
    ) -> TvWebContent? {
        let html: String

        switch descriptor.media {
        case .staticImage:
            return nil
        case .animatedImage:
            html = appendingLocalMediaFailureSignal(
                to: DownloadableTokenHTML.createImageHTML(
                    imageURL: fileURL.absoluteString,
                    nextImageURL: nextLocalFileURL?.absoluteString
                ),
                elementId: DownloadableTokenHTML.imageElementId
            )
        case .video:
            html = appendingLocalMediaFailureSignal(
                to: DownloadableTokenHTML.createVideoHTML(videoURL: fileURL.absoluteString),
                elementId: DownloadableTokenHTML.videoElementId
            )
        case .html:
            return nil
        }

        return .localHTML(
            string: html,
            directoryURL: DownloadableMediaCache.shared.webViewHTMLDirectoryURL
        )
    }

    private func adjacentLocalFileURL(for descriptor: CollectionCatalogDownloadableMediaDescriptor) -> URL? {
        guard let context,
              case .animatedImage = descriptor.media,
              let adjacentDescriptor = DownloadableMediaCache.adjacentDescriptor(
                for: context,
                direction: preferredPrefetchDirection
              ) else {
            return nil
        }

        return DownloadableMediaCache.shared.localFileURL(for: adjacentDescriptor)
    }

    private func handleLocalWebContentLoadFailure(
        for descriptor: CollectionCatalogDownloadableMediaDescriptor
    ) {
        guard localWebContentDescriptor == descriptor,
              downloadableMediaDescriptor == descriptor else {
            return
        }

        localWebContent = nil
        pendingHTMLDocumentRender = nil
        renderDownloadableMediaFallback(for: descriptor)
    }

    private func appendingLocalMediaFailureSignal(to html: String, elementId: String) -> String {
        let script = """
        <script>
        (function() {
            const element = document.getElementById("\(elementId)");
            if (!element) {
                window.location.href = "\(TvGeneratedTokenView.localMediaFailureURLString)";
                return;
            }
            element.addEventListener("error", function() {
                window.location.href = "\(TvGeneratedTokenView.localMediaFailureURLString)";
            }, { once: true });
        })();
        </script>
        """

        guard let bodyCloseRange = html.range(
            of: "</body>",
            options: [.caseInsensitive, .backwards]
        ) else {
            return html + "\n" + script
        }

        var html = html
        html.insert(contentsOf: "\n\(script)\n", at: bodyCloseRange.lowerBound)
        return html
    }

    private func clearDownloadableMediaFallback() {
        fallbackHTMLDescriptor = nil
    }

    private func renderDownloadableMediaFallback(
        for descriptor: CollectionCatalogDownloadableMediaDescriptor
    ) {
        guard downloadableMediaDescriptor == descriptor else {
            return
        }

        fallbackHTMLDescriptor = descriptor
    }

    private func cleanup() {
        cancelActiveLoadIfNeeded()
        DownloadableMediaCache.shared.clearActiveWindow(ownerId: ownerId)
        staticImage = nil
        staticImageDescriptor = nil
        localWebContent = nil
        localWebContentDescriptor = nil
        fallbackHTMLDescriptor = nil
        pendingHTMLDocumentRender = nil
    }

    private func cancelActiveLoadIfNeeded() {
        cancelActiveLoad?()
        cancelActiveLoad = nil
    }

    private func fallbackURL(for token: GeneratedToken) -> URL? {
        artBlocksMediaProxyFallbackURL(for: token)
    }

    private func fallbackURL(
        for token: GeneratedToken,
        descriptor: CollectionCatalogDownloadableMediaDescriptor?
    ) -> URL? {
        if let imageURL = directlyDecodableImageFallbackURL(for: descriptor) {
            return imageURL
        }
        return ethereumArtBlocksMediaProxyFallbackURL(for: token)
    }

    private func directlyDecodableImageFallbackURL(
        for descriptor: CollectionCatalogDownloadableMediaDescriptor?
    ) -> URL? {
        guard let descriptor else { return nil }

        switch descriptor.media {
        case .staticImage, .animatedImage:
            return descriptor.fileExtension == "svg" ? nil : descriptor.url
        case .video, .html:
            return nil
        }
    }

    private func artBlocksMediaProxyFallbackURL(for token: GeneratedToken) -> URL? {
        URL(string: "https://media-proxy.artblocks.io/\(token.address)/\(token.id).png")
    }

    private func ethereumArtBlocksMediaProxyFallbackURL(for token: GeneratedToken) -> URL? {
        let address = token.address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard address.lowercased().hasPrefix("0x"),
              address.count == 42,
              !token.id.isEmpty else {
            return nil
        }

        return URL(string: "https://media-proxy.artblocks.io/\(address)/\(token.id).png")
    }
}

private struct TvPlayerRenderKey: Hashable {
    let collectionId: String
    let tokenId: String
    let context: PlayerTokenContext?
    let media: GeneratedTokenMedia?
    let preferredPrefetchDirection: DownloadableMediaCache.PrefetchDirection
}

private struct TvHTMLDocumentRenderRequest: Hashable {
    let descriptor: CollectionCatalogDownloadableMediaDescriptor
    let fileURL: URL
}

enum TvPlayerPrewarmer {

    static func scheduleAfterLaunch(continueViewingProgress: PlayerViewingProgress?, initialCollectionIds: [String]) {
        TvGeneratedTokenView.scheduleFirstUsePrewarm()
        PlayerTokenPrewarmer.scheduleAfterLaunch(
            continueViewingProgress: continueViewingProgress,
            initialCollectionIds: initialCollectionIds
        )
    }

    static func preparedModel(
        initialItemId: String?,
        initialTokenId: String? = nil,
        continueViewingCollectionId: String? = nil
    ) -> PlayerModel {
        if let preparedToken = PlayerTokenPrewarmer.preparedToken(
            initialCollectionId: initialItemId,
            initialTokenId: initialTokenId
        ) {
            return PlayerModel(token: preparedToken)
        }
        if let initialItemId {
            return PlayerModel(
                collectionId: initialItemId,
                initialTokenId: initialTokenId,
                continueViewingCollectionId: continueViewingCollectionId ?? initialItemId
            )
        }
        return PlayerModel(specificCollectionId: nil, notTokenId: nil)
    }
}
