// ∅ 2026 lil org

import Foundation

struct MobileCollectionItem: Hashable, Identifiable {
    let id: String
    let name: String
    let coverAssetName: String

    init(item: SuggestedItem) {
        id = item.id
        name = item.name
        coverAssetName = item.id
    }
}

struct DownloadableMediaDescriptor: Hashable {
    let collectionId: String
    let tokenId: String
    let tokenIndex: Int
    let url: URL
    let fileExtension: String
    let media: GeneratedTokenMedia

    var isStaticImage: Bool {
        media.isStaticImage
    }
}

enum MobileCollectionCatalog {
    private static let shuffleLock = NSLock()
    private static var currentPassCollectionIds = Set<String>()

    static let allItems: [MobileCollectionItem] = {
        dedupedItems(
            generativeItemsForGrid
                + SuggestedItemsService.allDownloadableCollectionItems
        )
        .map(MobileCollectionItem.init(item:))
    }()

    static func nextShuffledCollectionId() -> String? {
        shuffleLock.withLock {
            if currentPassCollectionIds.isEmpty {
                currentPassCollectionIds = Set(allItems.map(\.id))
            }
            let nextCollectionId = currentPassCollectionIds.randomElement()
            if let nextCollectionId {
                currentPassCollectionIds.remove(nextCollectionId)
            }
            return nextCollectionId
        }
    }

    static func tokenCount(specificCollectionId: String) -> Int {
        if DownloadableCollectionService.hasCollection(id: specificCollectionId) {
            return DownloadableCollectionService.tokenCount(collectionId: specificCollectionId)
        }
        return TokenGenerator.tokenCount(specificCollectionId: specificCollectionId)
    }

    static func isDownloadableCollection(specificCollectionId: String) -> Bool {
        DownloadableCollectionService.hasCollection(id: specificCollectionId)
    }

    static func tokenIndex(specificCollectionId: String, tokenId: String) -> Int? {
        if DownloadableCollectionService.hasCollection(id: specificCollectionId) {
            return DownloadableCollectionService.tokenIndex(collectionId: specificCollectionId, tokenId: tokenId)
        }
        return TokenGenerator.tokenIndex(specificCollectionId: specificCollectionId, tokenId: tokenId)
    }

    static func generateToken(specificCollectionId: String, tokenIndex: Int) -> GeneratedToken? {
        if DownloadableCollectionService.hasCollection(id: specificCollectionId) {
            return DownloadableCollectionService.generateToken(collectionId: specificCollectionId, tokenIndex: tokenIndex)
        }
        return TokenGenerator.generateToken(specificCollectionId: specificCollectionId, tokenIndex: tokenIndex)
    }

    static func downloadableMediaDescriptor(specificCollectionId: String, tokenIndex: Int) -> DownloadableMediaDescriptor? {
        guard DownloadableCollectionService.hasCollection(id: specificCollectionId) else { return nil }
        return DownloadableCollectionService.mediaDescriptor(collectionId: specificCollectionId, tokenIndex: tokenIndex)
    }

    private static func dedupedItems(_ items: [SuggestedItem]) -> [SuggestedItem] {
        var seenIds = Set<String>()
        return items.filter { item in
            guard !seenIds.contains(item.id) else { return false }
            seenIds.insert(item.id)
            return true
        }
    }

    private static var generativeItemsForGrid: [SuggestedItem] {
        return TokenGenerator.allGenerativeSuggestedItems.filter {
            !$0.isSolanaCollection && !$0.isTezosCollection
        }
    }
}

struct DownloadableCollectionIndexItem: Codable, Hashable, Identifiable {
    let id: String
    let name: String
    let address: String
    let chain: Chain
    let network: Network
    let tokenCount: Int

    init?(item: SuggestedItem) {
        guard item.isDownloadableCollection,
              let tokenCount = item.tokenCount else {
            return nil
        }
        id = item.id
        name = item.name
        address = item.address
        chain = item.chain
        network = item.network
        self.tokenCount = tokenCount
    }
}

private enum DownloadableCollectionService {
    private static let collectionAddressOnlyBlockExplorerAddresses: Set<String> = [
        "0xc2276a4a03e7c2e2fa122692b07a870eff43cf51",
    ]
    private static let lock = NSLock()
    private static var cachedIndex: DownloadableCollectionsIndex?
    private static var cachedTokenDataByCollectionId = [String: DownloadableCollectionTokenData]()

    static func hasCollection(id: String) -> Bool {
        index.collectionById[id] != nil
    }

    static func tokenCount(collectionId: String) -> Int {
        tokenData(collectionId: collectionId)?.tokens.count
            ?? index.collectionById[collectionId]?.tokenCount
            ?? 0
    }

    static func tokenIndex(collectionId: String, tokenId: String) -> Int? {
        tokenData(collectionId: collectionId)?.tokenIndicesById[tokenId]
    }

    static func generateToken(collectionId: String, tokenIndex: Int) -> GeneratedToken? {
        guard let collection = index.collectionById[collectionId],
              let tokenData = tokenData(collectionId: collectionId),
              tokenData.tokens.indices.contains(tokenIndex) else {
            return nil
        }

        let token = tokenData.tokens[tokenIndex]
        let nextMedia = tokenData.tokens.indices.contains(tokenIndex + 1)
            ? resolvedMedia(
                for: tokenData.tokens[tokenIndex + 1],
                collection: collection,
                defaultFileExtension: tokenData.defaultFileExtension
            )
            : nil
        guard let media = resolvedMedia(
            for: token,
            collection: collection,
            defaultFileExtension: tokenData.defaultFileExtension
        ) else {
            return nil
        }

        let displayTokenId = Self.displayTokenId(
            chain: collection.chain,
            token: token,
            tokenIndex: tokenIndex
        )
        let webURL = Self.webURL(collection: collection, tokenId: token.id)

        let html: String
        switch media {
        case .staticImage, .animatedImage:
            html = DownloadableTokenHTML.createImageHTML(
                imageURL: media.url.absoluteString,
                nextImageURL: nextMedia?.url.absoluteString
            )
        case .video:
            html = DownloadableTokenHTML.createVideoHTML(videoURL: media.url.absoluteString)
        case .html:
            html = DownloadableTokenHTML.createHTMLDocumentHTML(documentURL: media.url.absoluteString)
        }

        return GeneratedToken(
            fullCollectionId: collection.id,
            collectionName: collection.name,
            address: collection.address,
            id: token.id,
            html: html,
            displayName: token.name ?? "\(collection.name) \(displayTokenId)",
            displayTokenId: displayTokenId,
            url: webURL,
            instructions: nil,
            screensaver: nil,
            media: media
        )
    }

    static func mediaDescriptor(collectionId: String, tokenIndex: Int) -> DownloadableMediaDescriptor? {
        guard let collection = index.collectionById[collectionId],
              let tokenData = tokenData(collectionId: collectionId),
              tokenData.tokens.indices.contains(tokenIndex) else {
            return nil
        }

        let token = tokenData.tokens[tokenIndex]
        guard let media = resolvedMedia(
            for: token,
            collection: collection,
            defaultFileExtension: tokenData.defaultFileExtension
        ) else {
            return nil
        }

        return DownloadableMediaDescriptor(
            collectionId: collectionId,
            tokenId: token.id,
            tokenIndex: tokenIndex,
            url: media.url,
            fileExtension: media.fileExtension,
            media: media
        )
    }

    private static func displayTokenId(
        chain: Chain,
        token: DownloadableTokenItem,
        tokenIndex: Int
    ) -> String {
        if chain == .solana {
            return "#\(tokenIndex + 1)"
        }
        return "#\(token.id)"
    }

    private static func webURL(collection: DownloadableCollectionIndexItem, tokenId: String) -> URL? {
        if collection.chain == .solana {
            return URL(string: "https://explorer.solana.com/address/\(tokenId)")
        }
        if collection.chain == .tezos {
            return URL(string: "https://tzkt.io/\(collection.address)/tokens/\(tokenId)")
        }
        let blockExplorerTokenId = collectionAddressOnlyBlockExplorerAddresses.contains(collection.address.lowercased())
            ? nil
            : tokenId
        return NftGallery.blockExplorer.url(
            network: collection.network,
            chain: collection.chain,
            collectionAddress: collection.address,
            tokenId: blockExplorerTokenId
        )
    }

    private static func resolvedMedia(
        for token: DownloadableTokenItem,
        collection: DownloadableCollectionIndexItem,
        defaultFileExtension: String?
    ) -> GeneratedTokenMedia? {
        guard let urlString = token.resolvedURLString(collection: collection),
              let url = URL(string: urlString),
              let fileExtension = token.resolvedFileExtension(
                collection: collection,
                defaultFileExtension: defaultFileExtension
              ) else {
            return nil
        }

        if DownloadableMediaFileExtension.isAnimatedImage(fileExtension) {
            return .animatedImage(url: url, fileExtension: fileExtension)
        }
        if DownloadableMediaFileExtension.isVideo(fileExtension) {
            return .video(url: url, fileExtension: fileExtension)
        }
        if DownloadableMediaFileExtension.isHTML(fileExtension) {
            return .html(url: url, fileExtension: fileExtension)
        }
        if DownloadableMediaFileExtension.isStaticImage(fileExtension) {
            return .staticImage(url: url, fileExtension: fileExtension)
        }
        return nil
    }

    private static var index: DownloadableCollectionsIndex {
        if let cachedIndex = lock.withLock({ cachedIndex }) {
            return cachedIndex
        }

        let loadedIndex = loadIndex()
        return lock.withLock {
            if let cachedIndex = Self.cachedIndex {
                return cachedIndex
            }
            Self.cachedIndex = loadedIndex
            return loadedIndex
        }
    }

    private static func tokenData(collectionId: String) -> DownloadableCollectionTokenData? {
        if let cachedTokenData = lock.withLock({ cachedTokenDataByCollectionId[collectionId] }) {
            return cachedTokenData
        }

        guard let loadedTokenData = loadTokenData(collectionId: collectionId) else {
            return nil
        }

        return lock.withLock {
            if let cachedTokenData = cachedTokenDataByCollectionId[collectionId] {
                return cachedTokenData
            }
            cachedTokenDataByCollectionId[collectionId] = loadedTokenData
            return loadedTokenData
        }
    }

    private static func loadIndex() -> DownloadableCollectionsIndex {
        DownloadableCollectionsIndex(
            collections: SuggestedItemsService.allDownloadableCollectionItems.compactMap(DownloadableCollectionIndexItem.init(item:))
        )
    }

    private static func loadTokenData(collectionId: String) -> DownloadableCollectionTokenData? {
        guard let collection = index.collectionById[collectionId],
              let url = SuggestedItemsService.bundle.url(forResource: collectionId, withExtension: "json", subdirectory: "Tokens")
                ?? SuggestedItemsService.bundle.url(forResource: collectionId.lowercased(), withExtension: "json", subdirectory: "Tokens"),
              let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(DownloadableCollectionTokensPayload.self, from: data) else {
            return nil
        }
        return DownloadableCollectionTokenData(
            defaultFileExtension: payload.defaultFileExtension,
            tokens: payload.items.filter {
                resolvedMedia(
                    for: $0,
                    collection: collection,
                    defaultFileExtension: payload.defaultFileExtension
                ) != nil
            }
        )
    }
}

private struct DownloadableCollectionsIndex {
    let collections: [DownloadableCollectionIndexItem]
    let collectionById: [String: DownloadableCollectionIndexItem]

    init(collections: [DownloadableCollectionIndexItem]) {
        self.collections = collections
        collectionById = Dictionary(uniqueKeysWithValues: collections.map { ($0.id, $0) })
    }
}

private struct DownloadableCollectionTokensPayload: Decodable {
    let defaultFileExtension: String?
    let items: [DownloadableTokenItem]

    enum CodingKeys: String, CodingKey {
        case defaultFileExtension
        case items
        case urlPrefixes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        defaultFileExtension = Self.normalizedFileExtension(
            try container.decodeIfPresent(String.self, forKey: .defaultFileExtension)
        )
        let urlPrefixes = try container.decodeIfPresent([String].self, forKey: .urlPrefixes) ?? []

        if let compactRows = try? container.decode([DownloadableCompactTokenRow].self, forKey: .items) {
            items = compactRows.map { row in
                DownloadableTokenItem(
                    id: row.id,
                    name: nil,
                    url: row.url(prefixes: urlPrefixes),
                    sh: nil,
                    fileExtension: row.fileExtension
                )
            }
        } else {
            items = try container.decode([DownloadableTokenItem].self, forKey: .items).map { item in
                DownloadableTokenItem(
                    id: item.id,
                    name: item.name,
                    url: item.url,
                    sh: item.sh,
                    fileExtension: Self.normalizedFileExtension(item.fileExtension)
                )
            }
        }
    }

    private static func normalizedFileExtension(_ value: String?) -> String? {
        DownloadableMediaFileExtension.normalized(value)
    }
}

private struct DownloadableTokenItem: Codable, Hashable {
    let id: String
    let name: String?
    let url: String?
    let sh: String?
    let fileExtension: String?

    func resolvedURLString(collection: DownloadableCollectionIndexItem) -> String? {
        if let url {
            return url
        }
        if let sh {
            return "https://cdn.simplehash.com/assets/\(sh)"
        }
        if collection.chain == .ethereum {
            return "https://media-proxy.artblocks.io/\(collection.address)/\(id).png"
        }
        return nil
    }

    func resolvedFileExtension(
        collection: DownloadableCollectionIndexItem,
        defaultFileExtension: String?
    ) -> String? {
        guard let url = resolvedURLString(collection: collection) else { return nil }
        return DownloadableMediaFileExtension.explicitPathExtension(in: url)
            ?? DownloadableMediaFileExtension.normalized(fileExtension)
            ?? defaultFileExtension
    }
}

private struct DownloadableCompactTokenRow: Decodable {
    let id: String
    let prefixIndex: Int
    let urlSuffix: String
    let fileExtension: String?

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        id = try container.decode(String.self)
        prefixIndex = try container.decode(Int.self)
        urlSuffix = try container.decode(String.self)
        fileExtension = DownloadableMediaFileExtension.normalized(try? container.decode(String.self))
    }

    func url(prefixes: [String]) -> String {
        guard prefixes.indices.contains(prefixIndex) else { return urlSuffix }
        return prefixes[prefixIndex] + urlSuffix
    }
}

private struct DownloadableCollectionTokenData {
    let defaultFileExtension: String?
    let tokens: [DownloadableTokenItem]
    let tokenIndicesById: [String: Int]

    init(defaultFileExtension: String?, tokens: [DownloadableTokenItem]) {
        self.defaultFileExtension = defaultFileExtension
        self.tokens = tokens

        var tokenIndicesById = [String: Int]()
        for (index, token) in tokens.enumerated() where tokenIndicesById[token.id] == nil {
            tokenIndicesById[token.id] = index
        }
        self.tokenIndicesById = tokenIndicesById
    }
}

private enum DownloadableMediaFileExtension {
    private static let staticImageExtensions = Set(["png", "jpg", "jpeg", "webp", "heic", "heif"])
    private static let animatedImageExtensions = Set(["gif", "svg"])
    private static let videoExtensions = Set(["mp4", "mov"])
    private static let htmlExtensions = Set(["html", "htm", "xhtml"])

    static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: CharacterSet(charactersIn: ". \n\t\r")).lowercased()
        return normalized.isEmpty ? nil : normalized
    }

    static func explicitPathExtension(in urlString: String) -> String? {
        guard let url = URL(string: urlString) else {
            return nil
        }
        return normalized(url.pathExtension)
    }

    static func isStaticImage(_ fileExtension: String) -> Bool {
        staticImageExtensions.contains(fileExtension)
    }

    static func isAnimatedImage(_ fileExtension: String) -> Bool {
        animatedImageExtensions.contains(fileExtension)
    }

    static func isVideo(_ fileExtension: String) -> Bool {
        videoExtensions.contains(fileExtension)
    }

    static func isHTML(_ fileExtension: String) -> Bool {
        htmlExtensions.contains(fileExtension)
    }
}

enum DownloadableTokenHTML {
    private static let trustedHTMLDocumentSandbox = "allow-scripts allow-same-origin"

    static func createImageHTML(imageURL: String, nextImageURL: String? = nil) -> String {
        """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, viewport-fit=cover">
        <style>
        html, body {
            width: 100%;
            height: 100%;
            margin: 0;
            padding: 0;
            background: transparent;
            overflow: hidden;
        }
        body {
            display: flex;
            align-items: center;
            justify-content: center;
        }
        #tokenImage {
            width: 100%;
            height: 100%;
            object-fit: contain;
            display: block;
        }
        </style>
        </head>
        <body>
        <img id="tokenImage" alt="">
        <script>
        \(retainedPreloadFunctionJavaScript)
        const imageURL = \(javaScriptStringLiteral(imageURL));
        const nextImageURL = \(javaScriptStringLiteral(nextImageURL));
        const tokenImage = document.getElementById("tokenImage");
        tokenImage.decoding = "async";
        tokenImage.src = imageURL;

        if (nextImageURL) {
            retainDownloadableTokenImagePreload(nextImageURL);
        }
        </script>
        </body>
        </html>
        """
    }

    static func createVideoHTML(videoURL: String) -> String {
        """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, viewport-fit=cover">
        <style>
        html, body {
            width: 100%;
            height: 100%;
            margin: 0;
            padding: 0;
            background: transparent;
            overflow: hidden;
        }
        body {
            display: flex;
            align-items: center;
            justify-content: center;
        }
        #tokenVideo {
            width: 100%;
            height: 100%;
            object-fit: contain;
            display: block;
        }
        </style>
        </head>
        <body>
        <video id="tokenVideo" autoplay loop muted playsinline webkit-playsinline preload="auto"></video>
        <script>
        const videoURL = \(javaScriptStringLiteral(videoURL));
        const tokenVideo = document.getElementById("tokenVideo");
        tokenVideo.muted = true;
        tokenVideo.loop = true;
        tokenVideo.playsInline = true;
        tokenVideo.autoplay = true;
        tokenVideo.src = videoURL;

        function playTokenVideo() {
            const playPromise = tokenVideo.play();
            if (playPromise && playPromise.catch) {
                playPromise.catch(() => {});
            }
        }

        tokenVideo.addEventListener("canplay", playTokenVideo, { once: true });
        tokenVideo.addEventListener("loadeddata", playTokenVideo, { once: true });
        document.addEventListener("visibilitychange", () => {
            if (!document.hidden) {
                playTokenVideo();
            }
        });
        playTokenVideo();
        </script>
        </body>
        </html>
        """
    }

    static func createHTMLDocumentHTML(documentURL: String) -> String {
        createHTMLDocumentFrameHTML(
            iframeSandbox: trustedHTMLDocumentSandbox,
            iframeSourceJavaScript: """
        const documentURL = \(javaScriptStringLiteral(documentURL));
        document.getElementById("tokenDocument").src = documentURL;
        """
        )
    }

    static func createInlineHTMLDocumentHTML(documentHTML: String, baseURL: String?) -> String {
        let documentHTML = htmlDocument(documentHTML, insertingBaseURL: baseURL)
        return createHTMLDocumentFrameHTML(
            iframeSandbox: trustedHTMLDocumentSandbox,
            iframeSourceJavaScript: """
        const documentHTML = \(javaScriptStringLiteral(documentHTML));
        document.getElementById("tokenDocument").srcdoc = documentHTML;
        """
        )
    }

    private static func createHTMLDocumentFrameHTML(
        iframeSandbox: String,
        iframeSourceJavaScript: String
    ) -> String {
        """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, viewport-fit=cover">
        <style>
        html, body {
            width: 100%;
            height: 100%;
            margin: 0;
            padding: 0;
            background: transparent;
            overflow: hidden;
        }
        #tokenDocument {
            width: 100%;
            height: 100%;
            border: 0;
            display: block;
            background: transparent;
        }
        </style>
        </head>
        <body>
        <iframe id="tokenDocument" sandbox="\(iframeSandbox)" allow="autoplay; fullscreen"></iframe>
        <script>
        \(iframeSourceJavaScript)
        </script>
        </body>
        </html>
        """
    }

    static func preloadImageJavaScript(imageURL: URL) -> String {
        """
        \(retainedPreloadFunctionJavaScript)
        return await retainDownloadableTokenImagePreload(\(javaScriptStringLiteral(imageURL.absoluteString)));
        """
    }

    private static var retainedPreloadFunctionJavaScript: String {
        """
        function retainDownloadableTokenImagePreload(url) {
            if (!url) {
                return Promise.resolve(false);
            }

            const maximumRetainedPreloads = 4;
            const releasePreload = (entry) => {
                if (!entry) {
                    return;
                }
                if (entry.cancel) {
                    entry.cancel();
                    return;
                }
                if (entry.timeoutId) {
                    clearTimeout(entry.timeoutId);
                    entry.timeoutId = null;
                }
                if (entry.image) {
                    entry.image.onload = null;
                    entry.image.onerror = null;
                    entry.image.removeAttribute("src");
                }
                entry.promise = null;
            };

            let existingPreloads = window.__downloadableTokenImagePreloads || [];
            const existingPreload = existingPreloads.find((entry) => entry.url === url);
            if (existingPreload) {
                if (existingPreload.promise) {
                    return existingPreload.promise;
                }
                if (existingPreload.didLoad === true) {
                    return Promise.resolve(true);
                }

                const existingImage = existingPreload.image;
                if (existingImage && existingImage.complete && (existingImage.naturalWidth > 0 || existingImage.naturalHeight > 0)) {
                    existingPreload.didLoad = true;
                    return Promise.resolve(true);
                }

                existingPreloads = existingPreloads.filter((entry) => entry !== existingPreload);
                releasePreload(existingPreload);
            }

            const preloadImage = new Image();
            const preloadEntry = {
                url,
                image: preloadImage,
                didLoad: false,
                promise: null,
                timeoutId: null,
                cancel: null
            };
            let finishPreload = null;
            const preloadPromise = new Promise((resolve) => {
                let didFinish = false;
                const finish = (didLoad) => {
                    if (didFinish) {
                        return;
                    }
                    didFinish = true;
                    if (preloadEntry.timeoutId) {
                        clearTimeout(preloadEntry.timeoutId);
                        preloadEntry.timeoutId = null;
                    }
                    preloadImage.onload = null;
                    preloadImage.onerror = null;
                    preloadEntry.didLoad = didLoad;
                    preloadEntry.promise = null;
                    preloadEntry.cancel = null;
                    resolve(didLoad);
                };
                finishPreload = finish;

                preloadEntry.timeoutId = setTimeout(() => finish(false), 8000);
                preloadImage.onload = () => finish(true);
                preloadImage.onerror = () => finish(false);
            });
            preloadEntry.promise = preloadPromise;
            preloadEntry.cancel = () => {
                preloadImage.onload = null;
                preloadImage.onerror = null;
                preloadImage.removeAttribute("src");
                if (finishPreload) {
                    finishPreload(false);
                }
            };

            preloadImage.decoding = "async";
            preloadImage.src = url;
            Promise.resolve().then(() => {
                if (preloadImage.complete && finishPreload) {
                    finishPreload(preloadImage.naturalWidth > 0 || preloadImage.naturalHeight > 0);
                }
            });

            const nextPreloads = existingPreloads.concat(preloadEntry);
            const evictedPreloads = nextPreloads.slice(0, Math.max(0, nextPreloads.length - maximumRetainedPreloads));
            window.__downloadableTokenImagePreloads = nextPreloads.slice(-maximumRetainedPreloads);
            evictedPreloads.forEach(releasePreload);
            return preloadPromise;
        }
        """
    }

    private static func htmlDocument(_ html: String, insertingBaseURL baseURL: String?) -> String {
        guard let baseURL,
              !baseURL.isEmpty,
              openingTagRange("base", in: html) == nil else {
            return html
        }

        let baseElement = "<base href=\"\(htmlAttributeValue(baseURL))\">"
        if let headRange = openingTagRange("head", in: html) {
            var html = html
            html.insert(contentsOf: "\n\(baseElement)", at: headRange.upperBound)
            return html
        }

        if let htmlRange = openingTagRange("html", in: html) {
            var html = html
            html.insert(contentsOf: "\n<head>\(baseElement)</head>", at: htmlRange.upperBound)
            return html
        }

        return "\(baseElement)\n\(html)"
    }

    private static func openingTagRange(_ tagName: String, in html: String) -> Range<String.Index>? {
        html.range(
            of: "<\(tagName)(?=\\s|/?>)[^>]*>",
            options: [.regularExpression, .caseInsensitive]
        )
    }

    private static func htmlAttributeValue(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func javaScriptStringLiteral(_ value: String?) -> String {
        guard let value,
              let data = try? JSONEncoder().encode(value),
              var literal = String(data: data, encoding: .utf8) else {
            return "null"
        }
        literal = literal
            .replacingOccurrences(of: "<", with: "\\u003C")
            .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
            .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
        return literal
    }
}
