// ∅ 2026 lil org

import SwiftUI
import UIKit

struct VisionPlayerConfig: Hashable, Identifiable {
    var id = UUID()
    var initialItemId: String?
    var specificToken: GeneratedToken?
    var initialTokenId: String?
}

struct VisionPlayerView: View {
    
    private let onDismiss: () -> Void
    @State private var playerState: VisionPlayerState
    
    init(config: VisionPlayerConfig, onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
        _playerState = State(initialValue: VisionPlayerState(config: config))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            VisionPlayerMediaView(
                token: playerState.currentToken,
                context: playerState.currentTokenContext,
                ownerId: playerState.id,
                preferredPrefetchDirection: playerState.preferredPrefetchDirection
            )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack {
                Button(action: onDismiss) {
                    Images.back
                }
                .accessibilityLabel(Strings.back)

                Spacer()

                HStack {
                    Button(action: goBack) {
                        Images.back
                    }
                    .keyboardShortcut("[", modifiers: .command)
                    .disabled(!playerState.canGoBack)
                    .accessibilityLabel(Strings.back)

                    Button(action: goForward) {
                        Images.forward
                    }
                    .keyboardShortcut("]", modifiers: .command)
                    .disabled(!playerState.canGoForward)
                    .accessibilityLabel(Strings.forward)
                }

                Spacer()

                moreMenu
            }
            .padding()
        }
        .background(Color.black)
        .onDisappear {
            DownloadableMediaCache.shared.clearActiveWindow(ownerId: playerState.id)
        }
    }

    private var moreMenu: some View {
        Menu {
            Button(Strings.viewOnBlockExplorer, action: viewOnWeb)
                .disabled(playerState.currentToken.url == nil)
        } label: {
            Images.ellipsis
        }
        .accessibilityLabel(Strings.more)
    }
    
    private func viewOnWeb() {
        if let url = playerState.currentToken.url {
            UIApplication.shared.open(url)
        }
    }

    private func goBack() {
        playerState.goBack()
    }

    private func goForward() {
        playerState.goForward()
    }

}

private struct VisionPlayerState {

    let id: UUID
    private let dataSource: PlayerTokenPagingDataSource
    private(set) var currentToken: GeneratedToken
    private(set) var currentCoordinate = PlayerCoordinate(x: 0, y: 0)
    private(set) var preferredPrefetchDirection: DownloadableMediaCache.PrefetchDirection = .forward

    init(config: VisionPlayerConfig) {
        id = config.id
        dataSource = PlayerTokenPagingDataSource(
            initialCollectionId: config.initialItemId,
            specificInitialToken: config.specificToken,
            initialTokenId: config.initialTokenId
        )
        currentToken = dataSource.getToken(coordinate: currentCoordinate)
    }

    var currentTokenContext: PlayerTokenContext? {
        dataSource.collectionTokenContext(coordinate: currentCoordinate)
    }

    var canGoBack: Bool {
        canRender(offset: -1)
    }

    var canGoForward: Bool {
        canRender(offset: 1)
    }

    mutating func goBack() {
        showCoordinate(
            PlayerCoordinate(x: currentCoordinate.x - 1, y: currentCoordinate.y),
            direction: .backward
        )
    }

    mutating func goForward() {
        showCoordinate(
            PlayerCoordinate(x: currentCoordinate.x + 1, y: currentCoordinate.y),
            direction: .forward
        )
    }

    private func canRender(offset: Int) -> Bool {
        dataSource.canRender(
            coordinate: PlayerCoordinate(
                x: currentCoordinate.x + offset,
                y: currentCoordinate.y
            )
        )
    }

    private mutating func showCoordinate(
        _ coordinate: PlayerCoordinate,
        direction: DownloadableMediaCache.PrefetchDirection
    ) {
        guard dataSource.canRender(coordinate: coordinate) else {
            return
        }

        currentCoordinate = coordinate
        preferredPrefetchDirection = direction
        currentToken = dataSource.getToken(coordinate: coordinate)
    }

}

private struct VisionPlayerMediaView: View {

    private static let htmlDocumentRenderQueue = DispatchQueue(
        label: "org.lil.nft-folder.vision-html-document-render",
        qos: .userInitiated
    )

    let token: GeneratedToken
    let context: PlayerTokenContext?
    let ownerId: UUID
    let preferredPrefetchDirection: DownloadableMediaCache.PrefetchDirection

    @State private var staticImage: UIImage?
    @State private var staticImageDescriptor: CollectionCatalogDownloadableMediaDescriptor?
    @State private var localWebContent: VisionWebContent?
    @State private var localWebContentDescriptor: CollectionCatalogDownloadableMediaDescriptor?
    @State private var fallbackHTMLDescriptor: CollectionCatalogDownloadableMediaDescriptor?
    @State private var pendingHTMLDocumentRender: VisionHTMLDocumentRenderRequest?
    @State private var cancelActiveLoad: (() -> Void)?

    var body: some View {
        content
            .onAppear(perform: renderCurrentContent)
            .onChange(of: renderKey) {
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
                VisionWebView(
                    content: localWebContent,
                    onLocalLoadFailure: {
                        handleLocalWebContentLoadFailure(for: descriptor)
                    }
                )
            } else if fallbackHTMLDescriptor == descriptor {
                VisionWebView(htmlString: token.html)
            } else {
                Color.black
            }
        } else {
            VisionWebView(htmlString: token.html)
        }
    }

    private var renderKey: VisionPlayerRenderKey {
        VisionPlayerRenderKey(
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
        guard let descriptor = DownloadableMediaCache.shared.prepareWindow(
            for: context,
            ownerId: ownerId,
            direction: preferredPrefetchDirection
        ) else {
            DownloadableMediaCache.shared.clearActiveWindow(ownerId: ownerId)
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
            cancelActiveLoad?()
            cancelActiveLoad = nil
            staticImage = nil
            staticImageDescriptor = descriptor
            clearDownloadableMediaFallback()
        }

        if let cachedImage = DownloadableMediaCache.shared.cachedDecodedImage(for: descriptor) {
            cancelActiveLoad?()
            cancelActiveLoad = nil
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
            cancelActiveLoad?()
            cancelActiveLoad = nil
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

        if pendingHTMLDocumentRender == VisionHTMLDocumentRenderRequest(
            descriptor: descriptor,
            fileURL: localFileURL
        ) {
            return
        }

        cancelActiveLoad?()
        cancelActiveLoad = nil
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
        let request = VisionHTMLDocumentRenderRequest(descriptor: descriptor, fileURL: fileURL)
        guard pendingHTMLDocumentRender != request else { return }

        pendingHTMLDocumentRender = request
        localWebContent = nil
        clearDownloadableMediaFallback()

        let htmlDirectoryURL = DownloadableMediaCache.shared.webViewHTMLDirectoryURL

        Self.htmlDocumentRenderQueue.async {
            let baseURL = DownloadableMediaCache.shared.downloadedSourceURL(for: descriptor).absoluteString
            let content = (try? String(contentsOf: fileURL, encoding: .utf8)).map { documentHTML in
                let viewportSize = DownloadableTokenHTMLLayout.rootSVGViewBoxSize(in: documentHTML)

                return VisionWebContent.localHTML(
                    string: DownloadableTokenHTML.createInlineHTMLDocumentHTML(
                        documentHTML: documentHTML,
                        baseURL: baseURL,
                        contentSize: viewportSize
                    ),
                    htmlDirectoryURL: htmlDirectoryURL,
                    readAccessURL: htmlDirectoryURL
                )
            }

            DispatchQueue.main.async {
                guard pendingHTMLDocumentRender == request,
                      localWebContentDescriptor == descriptor else {
                    return
                }

                pendingHTMLDocumentRender = nil
                guard let content else {
                    localWebContent = nil
                    renderDownloadableMediaFallback(for: descriptor)
                    return
                }

                clearDownloadableMediaFallback()
                localWebContent = content
            }
        }
    }

    private func localWebContent(
        for descriptor: CollectionCatalogDownloadableMediaDescriptor,
        fileURL: URL,
        nextLocalFileURL: URL?
    ) -> VisionWebContent? {
        let cache = DownloadableMediaCache.shared
        let html: String
        let readAccessURL: URL

        switch descriptor.media {
        case .staticImage:
            return nil
        case .animatedImage:
            html = DownloadableTokenHTML.createImageHTML(
                imageURL: fileURL.absoluteString,
                nextImageURL: nextLocalFileURL?.absoluteString
            )
            readAccessURL = cache.webViewReadAccessURL
        case .video:
            html = DownloadableTokenHTML.createVideoHTML(videoURL: fileURL.absoluteString)
            readAccessURL = cache.webViewReadAccessURL
        case .html:
            return nil
        }

        return .localHTML(
            string: html,
            htmlDirectoryURL: cache.webViewHTMLDirectoryURL,
            readAccessURL: readAccessURL
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
        cancelActiveLoad?()
        cancelActiveLoad = nil
        staticImage = nil
        staticImageDescriptor = nil
        localWebContent = nil
        localWebContentDescriptor = nil
        fallbackHTMLDescriptor = nil
        pendingHTMLDocumentRender = nil
    }

}

private struct VisionPlayerRenderKey: Hashable {
    let collectionId: String
    let tokenId: String
    let context: PlayerTokenContext?
    let media: GeneratedTokenMedia?
    let preferredPrefetchDirection: DownloadableMediaCache.PrefetchDirection
}

private struct VisionHTMLDocumentRenderRequest: Hashable {
    let descriptor: CollectionCatalogDownloadableMediaDescriptor
    let fileURL: URL
}

enum VisionPlayerPrewarmer {

    static func scheduleAfterLaunch(initialCollectionIds: [String]) {
        VisionPlayerWebView.scheduleFirstUsePrewarm()
        PlayerTokenPrewarmer.scheduleAfterLaunch(
            continueViewingProgress: nil,
            initialCollectionIds: initialCollectionIds
        )
    }

    static func preparedConfig(
        initialItemId: String?,
        initialTokenId: String? = nil
    ) -> VisionPlayerConfig {
        var config = VisionPlayerConfig(
            initialItemId: initialItemId,
            initialTokenId: initialTokenId
        )
        config.specificToken = PlayerTokenPrewarmer.preparedToken(
            initialCollectionId: initialItemId,
            initialTokenId: initialTokenId
        )
        return config
    }

}
