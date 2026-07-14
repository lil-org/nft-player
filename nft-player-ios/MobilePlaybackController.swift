// ∅ 2026 lil org

import UIKit

protocol MobilePlaybackControllerDisplay: AnyObject {

    func navigate(_ direction: PlaybackNavigationDirection)
    func getCurrentPagePosition() -> PlayerPagePosition

}

struct MobilePlayerFileShareItem {
    let fileURL: URL
    let previewTitle: String
    let previewImage: () -> UIImage?
    private let retainedFile: MobilePlayerFileShareRetainedFile

    init(
        fileURL: URL,
        previewTitle: String,
        releaseFile: @escaping () -> Void,
        previewImage: @escaping () -> UIImage?
    ) {
        self.fileURL = fileURL
        self.previewTitle = previewTitle
        self.previewImage = previewImage
        self.retainedFile = MobilePlayerFileShareRetainedFile(releaseFile: releaseFile)
    }
}

private final class MobilePlayerFileShareRetainedFile {
    private let releaseFile: () -> Void

    init(releaseFile: @escaping () -> Void) {
        self.releaseFile = releaseFile
    }

    deinit {
        releaseFile()
    }
}

enum MobilePlayerPageLayout: CaseIterable, Hashable, Identifiable {
    case onePerPage
    case fourPerPage
    case sixPerPage
    case twelvePerPage
    case fifteenPerPage

    static let cardNftCollectionId = "HpGDYGz6aRUs5qbvp1dmWGKTicQctX4PixfcouAQDCHF"
    static let drifella2CollectionId = "7cHTjqr2S8uUCrG3TVFvFix3vcLjhPiwrtRsAeJtESRj"
    static let driladyCollectionId = "96THxzqE5yukFxzsqJaR2SrsLL2wJtuapi6827gkUD6T"
    static let johnCollectionId = "r1pCPYkbbpZWv7RCvuCMtpA3NSQY3fzVFo6HL43A4ot"
    static let miladyAura2AfterDeathCollectionId = "0x30f9efa712dde239a13a5fef1a8c7a6ac530a26d"
    static let miladyAuraPetzCollectionId = "0xc62e3fd5b02618f90dd07d1e478963038fa9089c"
    static let superMetalMonsCollectionId = "0x17abd4cc1382397ec2b675f98621c3ba809897desmm"

    private static let staticImageGridLayoutsByCollectionId: [String: MobilePlayerPageLayout] = {
        var layouts: [String: MobilePlayerPageLayout] = [
            cardNftCollectionId: .twelvePerPage,
            drifella2CollectionId: .fifteenPerPage,
            driladyCollectionId: .twelvePerPage,
            johnCollectionId: .twelvePerPage,
            miladyAura2AfterDeathCollectionId: .sixPerPage,
            miladyAuraPetzCollectionId: .sixPerPage,
            superMetalMonsCollectionId: .twelvePerPage,
        ]
        for renderKind in NativeMetalCardRenderKind.allCases {
            layouts[renderKind.collectionId] = .twelvePerPage
        }
        return layouts
    }()

    static let initialLayout = MobilePlayerPageLayout.onePerPage

    var id: Self { self }

    var pageSize: Int {
        switch self {
        case .onePerPage:
            return 1
        case .fourPerPage:
            return 4
        case .sixPerPage:
            return 6
        case .twelvePerPage:
            return 12
        case .fifteenPerPage:
            return 15
        }
    }

    var isStaticImageGrid: Bool {
        switch self {
        case .onePerPage:
            return false
        case .fourPerPage, .sixPerPage, .twelvePerPage, .fifteenPerPage:
            return true
        }
    }

    static func staticImageGridLayout(for descriptor: DownloadableMediaDescriptor?) -> MobilePlayerPageLayout? {
        guard let descriptor,
              descriptor.isStaticImage else {
            return nil
        }

        if TokenGenerator.isBundledWebGenerativeCollection(id: descriptor.collectionId) {
            return .fifteenPerPage
        }

        if let layout = staticImageGridLayoutsByCollectionId[descriptor.collectionId] {
            return layout
        }

        return descriptor.isStaticImageGridThumbnail ? .twelvePerPage : nil
    }

    static func staticImageGridFallbackImageSize(for descriptor: DownloadableMediaDescriptor) -> CGSize {
        if let renderKind = descriptor.nativeMetalCardRenderKind {
            return renderKind.staticImageSize
        }

        switch descriptor.collectionId {
        case cardNftCollectionId:
            return CGSize(width: 776, height: 1098)
        case drifella2CollectionId:
            return CGSize(width: 1200, height: 1295)
        case driladyCollectionId:
            return CGSize(width: 932, height: 1006)
        case miladyAuraPetzCollectionId, superMetalMonsCollectionId:
            return CGSize(width: 1, height: 1)
        default:
            return CGSize(width: 1, height: 1)
        }
    }

    static func staticImageGridImageSizes(
        for descriptors: [DownloadableMediaDescriptor],
        images: [UIImage?]
    ) -> [CGSize] {
        zip(descriptors, images).map { descriptor, image in
            image?.size ?? staticImageGridFallbackImageSize(for: descriptor)
        }
    }

    var title: String {
        switch self {
        case .onePerPage:
            return Strings.onePerPage
        case .fourPerPage:
            return Strings.fourPerPage
        case .sixPerPage:
            return Strings.sixPerPage
        case .twelvePerPage:
            return Strings.twelvePerPage
        case .fifteenPerPage:
            return Strings.fifteenPerPage
        }
    }

    func supports(descriptor: DownloadableMediaDescriptor?) -> Bool {
        guard isStaticImageGrid else { return true }
        return Self.staticImageGridLayout(for: descriptor) == self
    }

}

extension MobilePlayerFileShareItem {
    static func previewTitle(for token: GeneratedToken, progressText: String) -> String {
        let trimmedCollectionName = token.collectionName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDisplayName = token.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseTitle: String
        if !trimmedCollectionName.isEmpty {
            baseTitle = trimmedCollectionName
        } else if !trimmedDisplayName.isEmpty {
            baseTitle = trimmedDisplayName
        } else {
            baseTitle = Strings.nftPlayer
        }
        let trimmedProgressText = progressText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedProgressText.isEmpty ? baseTitle : "\(baseTitle) \(trimmedProgressText)"
    }
}

private enum MobileStaticImageGridMediaWindowLayout {
    static let decodedPreferredPageRadius = 2
    static let decodedOppositePageRadius = 1
    static let filePreferredPageRadius = 6
    static let fileOppositePageRadius = 2

    static func pageOffsets(
        direction: DownloadableMediaCache.PrefetchDirection,
        preferredRadius: Int,
        oppositeRadius: Int
    ) -> [Int] {
        PlayerDownloadableMediaWindowLayout.orderedOffsets(
            direction: direction,
            preferredRadius: preferredRadius,
            oppositeRadius: oppositeRadius
        )
    }
}

private struct MobileStaticImageGridCandidateDescriptorKey: Hashable {
    let collectionId: String
    let tokenIndex: Int

    init(collectionId: String, tokenIndex: Int) {
        self.collectionId = collectionId
        self.tokenIndex = tokenIndex
    }

    init(descriptor: DownloadableMediaDescriptor) {
        self.init(collectionId: descriptor.collectionId, tokenIndex: descriptor.tokenIndex)
    }

    init(context: PlayerTokenContext) {
        self.init(collectionId: context.collectionId, tokenIndex: context.tokenIndex)
    }
}

private struct MobileStaticImageGridMediaWindowDescriptors {
    let descriptors: [DownloadableMediaDescriptor]
    let decodedDescriptors: [DownloadableMediaDescriptor]
}

class MobilePlaybackController {
    
    private init() {}
    
    static let shared = MobilePlaybackController()
    
    private var displays = [UUID: MobilePlaybackControllerDisplay]()
    private var initialConfigs = [UUID: MobilePlayerConfig]()
    private var tokensDataSources = [UUID: PlayerTokenPagingDataSource]()
    private var viewingSessionTrackers = [UUID: PlayerViewingSessionTracker]()
    
    func goForward(uuid: UUID) {
        navigate(.forward, uuid: uuid)
    }
    
    func goBack(uuid: UUID) {
        navigate(.back, uuid: uuid)
    }

    func restartCollection(uuid: UUID) {
        suppressContinueViewingUntilMovementAfterRestart(uuid: uuid)
        navigate(.restartCollection, uuid: uuid)
    }

    private func navigate(_ direction: PlaybackNavigationDirection, uuid: UUID) {
        displays[uuid]?.navigate(direction)
    }
    
    func subscribe(config: MobilePlayerConfig, display: MobilePlaybackControllerDisplay) {
        displays[config.id] = display
        initialConfigs[config.id] = config
        viewingSessionTrackers[config.id] = PlayerViewingSessionTracker(
            continueViewingCollectionId: config.continueViewingCollectionId,
            trackingMode: config.trackingMode
        )
    }
    
    func stopAndDisconnect(uuid: UUID) {
        displays.removeValue(forKey: uuid)
        initialConfigs.removeValue(forKey: uuid)
        tokensDataSources.removeValue(forKey: uuid)
        viewingSessionTrackers.removeValue(forKey: uuid)
        if displays.isEmpty {
            DownloadableMediaCache.shared.cancelAllDownloads()
        } else {
            clearDownloadableMediaWindow(uuid: uuid)
        }
    }

    func clearDownloadableMediaWindow(uuid: UUID) {
        DownloadableMediaCache.shared.clearActiveWindow(ownerId: uuid)
    }
    
    func getToken(uuid: UUID, pagePosition: PlayerPagePosition) -> GeneratedToken {
        dataSource(uuid: uuid)?.getToken(pagePosition: pagePosition) ?? .empty
    }

    func canRender(uuid: UUID, pagePosition: PlayerPagePosition) -> Bool {
        dataSource(uuid: uuid)?.canRender(pagePosition: pagePosition) ?? false
    }

    func pageLabel(uuid: UUID, pagePosition: PlayerPagePosition) -> String? {
        dataSource(uuid: uuid)?.pageLabel(pagePosition: pagePosition)
    }

    func isInsertedWidgetToken(uuid: UUID, pagePosition: PlayerPagePosition) -> Bool {
        dataSource(uuid: uuid)?.isInsertedWidgetToken(pagePosition: pagePosition) ?? false
    }

    func layoutInteractionState(
        uuid: UUID,
        pageLayout: MobilePlayerPageLayout,
        pagePosition: PlayerPagePosition?
    ) -> MobilePlayerLayoutInteractionState {
        guard pageLayout == .onePerPage,
              let pagePosition,
              let currentDescriptor = staticImageGridMediaDescriptor(uuid: uuid, pagePosition: pagePosition),
              let staticImageGridPageLayout = MobilePlayerPageLayout.staticImageGridLayout(for: currentDescriptor) else {
            return .empty
        }

        let switchMode: MobilePlayerStaticImageGridSwitchMode = isInsertedWidgetToken(
            uuid: uuid,
            pagePosition: pagePosition
        )
            ? .direct(
                descriptors: staticImageGridDescriptorsAfterExitingWidgetInsertion(
                    uuid: uuid,
                    containing: pagePosition,
                    pageLayout: staticImageGridPageLayout
                )
            )
            : .animated(
                descriptors: staticImageGridDescriptors(
                    uuid: uuid,
                    containing: pagePosition,
                    pageLayout: staticImageGridPageLayout
                )
            )

        return MobilePlayerLayoutInteractionState(
            pageLayout: pageLayout,
            tokenIndex: currentDescriptor.tokenIndex,
            staticImageGridPageLayout: staticImageGridPageLayout,
            currentDescriptor: currentDescriptor,
            staticImageGridSwitchMode: switchMode
        )
    }

    func prepareDownloadableMediaWindow(
        uuid: UUID,
        pagePosition: PlayerPagePosition,
        direction: DownloadableMediaCache.PrefetchDirection,
        pageLayout: MobilePlayerPageLayout = .onePerPage
    ) -> PlayerDownloadableMediaWindow? {
        guard let window = dataSource(uuid: uuid)?.downloadableMediaWindow(
            pagePosition: pagePosition,
            direction: direction
        ) else {
            clearDownloadableMediaWindow(uuid: uuid)
            return nil
        }

        let preparedWindow = downloadableMediaWindow(
            window,
            includingStaticImageGridDescriptorsFor: pageLayout,
            uuid: uuid,
            pagePosition: pagePosition,
            direction: direction
        )
        DownloadableMediaCache.shared.prepareWindow(preparedWindow, ownerId: uuid)
        return preparedWindow
    }

    func prepareStaticImageGridMediaWindow(
        uuid: UUID,
        pagePosition: PlayerPagePosition,
        pageLayout: MobilePlayerPageLayout,
        direction: DownloadableMediaCache.PrefetchDirection
    ) -> PlayerDownloadableMediaWindow? {
        guard pageLayout.isStaticImageGrid,
              let currentDescriptor = staticImageGridMediaDescriptor(uuid: uuid, pagePosition: pagePosition),
              pageLayout.supports(descriptor: currentDescriptor) else {
            clearDownloadableMediaWindow(uuid: uuid)
            return nil
        }

        let mediaWindowDescriptors = staticImageGridMediaWindowDescriptors(
            uuid: uuid,
            containing: pagePosition,
            pageLayout: pageLayout,
            direction: direction
        )
        let gridDescriptors = mediaWindowDescriptors.descriptors
        guard !gridDescriptors.isEmpty else {
            clearDownloadableMediaWindow(uuid: uuid)
            return nil
        }

        let preparedWindow = PlayerDownloadableMediaWindow(
            currentDescriptor: currentDescriptor,
            descriptors: gridDescriptors,
            decodedDescriptors: mediaWindowDescriptors.decodedDescriptors,
            adjacentDescriptor: nil,
            decodedDescriptorCapacity: mediaWindowDescriptors.decodedDescriptors.count + 1
        )
        DownloadableMediaCache.shared.prepareWindow(preparedWindow, ownerId: uuid)
        return preparedWindow
    }

    private func downloadableMediaWindow(
        _ window: PlayerDownloadableMediaWindow,
        includingStaticImageGridDescriptorsFor pageLayout: MobilePlayerPageLayout,
        uuid: UUID,
        pagePosition: PlayerPagePosition,
        direction: DownloadableMediaCache.PrefetchDirection
    ) -> PlayerDownloadableMediaWindow {
        let staticImageGridCurrentDescriptor = MobileCollectionCatalog.staticImageGridMediaDescriptor(
            for: window.currentDescriptor
        )
        guard let resolvedStaticImageGridLayout = resolvedStaticImageGridLayout(
            requestedPageLayout: pageLayout,
            descriptor: staticImageGridCurrentDescriptor
        ) else {
            return window
        }

        let candidateDescriptorLookup = Self.candidateDescriptorLookup(for: window.descriptors)
        let usesStandardThumbnailDescriptors = staticImageGridCurrentDescriptor != window.currentDescriptor
        let gridDescriptors: [DownloadableMediaDescriptor]
        let decodedGridDescriptors: [DownloadableMediaDescriptor]
        if pageLayout.isStaticImageGrid || usesStandardThumbnailDescriptors {
            let mediaWindowDescriptors = staticImageGridMediaWindowDescriptors(
                uuid: uuid,
                containing: pagePosition,
                pageLayout: resolvedStaticImageGridLayout,
                direction: direction,
                matchingCollectionId: window.currentDescriptor.collectionId,
                candidateDescriptorLookup: candidateDescriptorLookup
            )
            gridDescriptors = mediaWindowDescriptors.descriptors
            decodedGridDescriptors = mediaWindowDescriptors.decodedDescriptors
        } else {
            gridDescriptors = staticImageGridDescriptors(
                uuid: uuid,
                containing: pagePosition,
                pageLayout: resolvedStaticImageGridLayout,
                matchingCollectionId: window.currentDescriptor.collectionId,
                candidateDescriptorLookup: candidateDescriptorLookup
            )
            decodedGridDescriptors = gridDescriptors
        }
        guard !gridDescriptors.isEmpty else { return window }

        if pageLayout.isStaticImageGrid && usesStandardThumbnailDescriptors {
            return PlayerDownloadableMediaWindow(
                currentDescriptor: staticImageGridCurrentDescriptor,
                descriptors: gridDescriptors,
                decodedDescriptors: decodedGridDescriptors,
                adjacentDescriptor: nil,
                decodedDescriptorCapacity: decodedGridDescriptors.count + 1
            )
        }

        let decodedDescriptorCapacity = max(
            PlayerDownloadableMediaWindowLayout.decodedWindowCapacity,
            decodedGridDescriptors.count + window.decodedDescriptors.count + 1
        )
        let descriptors: [DownloadableMediaDescriptor]
        let decodedDescriptors: [DownloadableMediaDescriptor]
        let preferredDownloadDescriptors: [DownloadableMediaDescriptor]
        if usesStandardThumbnailDescriptors {
            descriptors = [staticImageGridCurrentDescriptor]
                + window.decodedDescriptors
                + decodedGridDescriptors
                + gridDescriptors
                + window.descriptors
            decodedDescriptors = [staticImageGridCurrentDescriptor]
                + window.decodedDescriptors
                + decodedGridDescriptors
            preferredDownloadDescriptors = [staticImageGridCurrentDescriptor]
                + [window.adjacentDescriptor].compactMap { $0 }
        } else {
            descriptors = gridDescriptors + window.descriptors
            decodedDescriptors = decodedGridDescriptors + window.decodedDescriptors
            preferredDownloadDescriptors = []
        }

        return PlayerDownloadableMediaWindow(
            currentDescriptor: window.currentDescriptor,
            descriptors: descriptors,
            decodedDescriptors: decodedDescriptors,
            adjacentDescriptor: window.adjacentDescriptor,
            preferredDownloadDescriptors: preferredDownloadDescriptors,
            decodedDescriptorCapacity: decodedDescriptorCapacity
        )
    }

    private func resolvedStaticImageGridLayout(
        requestedPageLayout: MobilePlayerPageLayout,
        descriptor: DownloadableMediaDescriptor
    ) -> MobilePlayerPageLayout? {
        if requestedPageLayout.isStaticImageGrid {
            return requestedPageLayout.supports(descriptor: descriptor) ? requestedPageLayout : nil
        }

        return MobilePlayerPageLayout.staticImageGridLayout(for: descriptor)
    }

    private static func candidateDescriptorLookup(
        for descriptors: [DownloadableMediaDescriptor]
    ) -> [MobileStaticImageGridCandidateDescriptorKey: DownloadableMediaDescriptor] {
        var lookup = [MobileStaticImageGridCandidateDescriptorKey: DownloadableMediaDescriptor]()
        for descriptor in descriptors {
            let key = MobileStaticImageGridCandidateDescriptorKey(descriptor: descriptor)
            if lookup[key] == nil {
                lookup[key] = descriptor
            }
        }
        return lookup
    }

    func downloadableMediaDescriptor(uuid: UUID, pagePosition: PlayerPagePosition) -> DownloadableMediaDescriptor? {
        guard let context = downloadableMediaTokenContext(uuid: uuid, pagePosition: pagePosition) else {
            return nil
        }

        return MobileCollectionCatalog.downloadableMediaDescriptor(
            specificCollectionId: context.collectionId,
            tokenIndex: context.tokenIndex
        )
    }

    func supportsPageLayout(_ pageLayout: MobilePlayerPageLayout, uuid: UUID, pagePosition: PlayerPagePosition) -> Bool {
        pageLayout.supports(
            descriptor: staticImageGridMediaDescriptor(uuid: uuid, pagePosition: pagePosition)
        )
    }

    func staticImageGridLayout(uuid: UUID, pagePosition: PlayerPagePosition) -> MobilePlayerPageLayout? {
        MobilePlayerPageLayout.staticImageGridLayout(
            for: staticImageGridMediaDescriptor(uuid: uuid, pagePosition: pagePosition)
        )
    }

    func staticImageGridMediaDescriptor(
        uuid: UUID,
        pagePosition: PlayerPagePosition
    ) -> DownloadableMediaDescriptor? {
        guard let context = collectionTokenContext(uuid: uuid, pagePosition: pagePosition) else {
            return nil
        }

        return MobileCollectionCatalog.staticImageGridMediaDescriptor(
            specificCollectionId: context.collectionId,
            tokenIndex: context.tokenIndex
        )
    }

    func staticImageGridDescriptors(
        uuid: UUID,
        containing pagePosition: PlayerPagePosition,
        pageLayout: MobilePlayerPageLayout
    ) -> [DownloadableMediaDescriptor] {
        staticImageGridDescriptors(
            uuid: uuid,
            containing: pagePosition,
            pageLayout: pageLayout,
            matchingCollectionId: nil,
            candidateDescriptorLookup: [:]
        )
    }

    func staticImageGridDescriptorsAfterExitingWidgetInsertion(
        uuid: UUID,
        containing pagePosition: PlayerPagePosition,
        pageLayout: MobilePlayerPageLayout
    ) -> [DownloadableMediaDescriptor] {
        guard pageLayout.isStaticImageGrid else { return [] }

        let contexts = dataSource(uuid: uuid)?
            .tokenContextsAfterExitingWidgetInsertion(
                containing: pagePosition,
                pageSize: pageLayout.pageSize
            ) ?? []

        return supportedStaticImageGridDescriptors(
            pageLayout: pageLayout,
            matchingCollectionId: nil
        ) { offset in
            guard contexts.indices.contains(offset) else { return nil }
            let context = contexts[offset]
            return MobileCollectionCatalog.staticImageGridMediaDescriptor(
                specificCollectionId: context.collectionId,
                tokenIndex: context.tokenIndex
            )
        }
    }

    private func staticImageGridMediaWindowDescriptors(
        uuid: UUID,
        containing pagePosition: PlayerPagePosition,
        pageLayout: MobilePlayerPageLayout,
        direction: DownloadableMediaCache.PrefetchDirection,
        matchingCollectionId collectionId: String? = nil,
        candidateDescriptorLookup: [MobileStaticImageGridCandidateDescriptorKey: DownloadableMediaDescriptor] = [:]
    ) -> MobileStaticImageGridMediaWindowDescriptors {
        guard pageLayout.isStaticImageGrid else {
            return MobileStaticImageGridMediaWindowDescriptors(descriptors: [], decodedDescriptors: [])
        }

        let stablePagePosition = stablePagePosition(
            uuid: uuid,
            containing: pagePosition,
            pageLayout: pageLayout
        )
        let filePageOffsets = MobileStaticImageGridMediaWindowLayout.pageOffsets(
            direction: direction,
            preferredRadius: MobileStaticImageGridMediaWindowLayout.filePreferredPageRadius,
            oppositeRadius: MobileStaticImageGridMediaWindowLayout.fileOppositePageRadius
        )
        let decodedPageOffsets = Set(MobileStaticImageGridMediaWindowLayout.pageOffsets(
            direction: direction,
            preferredRadius: MobileStaticImageGridMediaWindowLayout.decodedPreferredPageRadius,
            oppositeRadius: MobileStaticImageGridMediaWindowLayout.decodedOppositePageRadius
        ))

        var descriptors = [DownloadableMediaDescriptor]()
        var decodedDescriptors = [DownloadableMediaDescriptor]()
        var usedDescriptors = Set<DownloadableMediaDescriptor>()
        var usedDecodedDescriptors = Set<DownloadableMediaDescriptor>()

        for pageOffset in filePageOffsets {
            let pageDescriptors = staticImageGridDescriptors(
                uuid: uuid,
                containing: stablePagePosition.advanced(by: pageOffset * pageLayout.pageSize),
                pageLayout: pageLayout,
                matchingCollectionId: collectionId,
                candidateDescriptorLookup: candidateDescriptorLookup
            )
            appendUniqueStaticImageGridDescriptors(
                pageDescriptors,
                to: &descriptors,
                usedDescriptors: &usedDescriptors
            )
            if decodedPageOffsets.contains(pageOffset) {
                appendUniqueStaticImageGridDescriptors(
                    pageDescriptors,
                    to: &decodedDescriptors,
                    usedDescriptors: &usedDecodedDescriptors
                )
            }
        }

        return MobileStaticImageGridMediaWindowDescriptors(
            descriptors: descriptors,
            decodedDescriptors: decodedDescriptors
        )
    }

    private func staticImageGridDescriptors(
        uuid: UUID,
        containing pagePosition: PlayerPagePosition,
        pageLayout: MobilePlayerPageLayout,
        matchingCollectionId collectionId: String?,
        candidateDescriptorLookup: [MobileStaticImageGridCandidateDescriptorKey: DownloadableMediaDescriptor]
    ) -> [DownloadableMediaDescriptor] {
        guard pageLayout.isStaticImageGrid else { return [] }

        let stablePagePosition = stablePagePosition(
            uuid: uuid,
            containing: pagePosition,
            pageLayout: pageLayout
        )

        return supportedStaticImageGridDescriptors(
            pageLayout: pageLayout,
            matchingCollectionId: collectionId
        ) { offset in
            let descriptorPagePosition = stablePagePosition.advanced(by: offset)
            return staticImageGridMediaDescriptor(
                uuid: uuid,
                pagePosition: descriptorPagePosition,
                candidateDescriptorLookup: candidateDescriptorLookup
            )
        }
    }

    private func appendUniqueStaticImageGridDescriptors(
        _ newDescriptors: [DownloadableMediaDescriptor],
        to descriptors: inout [DownloadableMediaDescriptor],
        usedDescriptors: inout Set<DownloadableMediaDescriptor>
    ) {
        for descriptor in newDescriptors where usedDescriptors.insert(descriptor).inserted {
            descriptors.append(descriptor)
        }
    }

    private func supportedStaticImageGridDescriptors(
        pageLayout: MobilePlayerPageLayout,
        matchingCollectionId collectionId: String?,
        descriptorAtOffset: (Int) -> DownloadableMediaDescriptor?
    ) -> [DownloadableMediaDescriptor] {
        var descriptors = [DownloadableMediaDescriptor]()
        descriptors.reserveCapacity(pageLayout.pageSize)
        for offset in 0..<pageLayout.pageSize {
            guard let descriptor = descriptorAtOffset(offset) else {
                break
            }
            let matchesCollection = collectionId.map { descriptor.collectionId == $0 } ?? true
            guard matchesCollection,
                  pageLayout.supports(descriptor: descriptor) else {
                break
            }
            descriptors.append(descriptor)
        }
        return descriptors
    }

    private func staticImageGridMediaDescriptor(
        uuid: UUID,
        pagePosition: PlayerPagePosition,
        candidateDescriptorLookup: [MobileStaticImageGridCandidateDescriptorKey: DownloadableMediaDescriptor]
    ) -> DownloadableMediaDescriptor? {
        guard let context = collectionTokenContext(uuid: uuid, pagePosition: pagePosition) else {
            return nil
        }

        let candidateKey = MobileStaticImageGridCandidateDescriptorKey(context: context)
        if let candidateDescriptor = candidateDescriptorLookup[candidateKey] {
            return MobileCollectionCatalog.staticImageGridMediaDescriptor(for: candidateDescriptor)
        }

        return MobileCollectionCatalog.staticImageGridMediaDescriptor(
            specificCollectionId: context.collectionId,
            tokenIndex: context.tokenIndex
        )
    }

    func stablePagePosition(
        uuid: UUID,
        containing pagePosition: PlayerPagePosition,
        pageLayout: MobilePlayerPageLayout
    ) -> PlayerPagePosition {
        dataSource(uuid: uuid)?.stablePagePosition(
            containing: pagePosition,
            pageSize: pageLayout.pageSize
        ) ?? pagePosition
    }

    func exitWidgetInsertionForStablePage(
        uuid: UUID,
        containing pagePosition: PlayerPagePosition,
        pageLayout: MobilePlayerPageLayout
    ) -> PlayerStablePagePositionResolution {
        dataSource(uuid: uuid)?.exitWidgetInsertionForStablePage(
            containing: pagePosition,
            pageSize: pageLayout.pageSize
        ) ?? .resolved(
            pagePosition: pagePosition,
            didExitWidgetInsertion: false
        )
    }

    func navigationStride(
        uuid: UUID,
        from pagePosition: PlayerPagePosition,
        pageLayout: MobilePlayerPageLayout
    ) -> Int {
        guard pageLayout.isStaticImageGrid,
              supportsPageLayout(pageLayout, uuid: uuid, pagePosition: pagePosition) else {
            return MobilePlayerPageLayout.onePerPage.pageSize
        }

        return pageLayout.pageSize
    }

    func hasNavigationDestination(
        uuid: UUID,
        from pagePosition: PlayerPagePosition,
        pageLayout: MobilePlayerPageLayout,
        direction: PlaybackNavigationDirection
    ) -> Bool {
        guard direction.isPagingDirection else { return false }

        let stride = navigationStride(uuid: uuid, from: pagePosition, pageLayout: pageLayout)
        guard let targetOffset = direction.pageOffset(forStride: stride) else { return false }

        return canRender(uuid: uuid, pagePosition: pagePosition.advanced(by: targetOffset))
    }

    private func downloadableMediaTokenContext(
        uuid: UUID,
        pagePosition: PlayerPagePosition
    ) -> PlayerTokenContext? {
        guard let dataSource = dataSource(uuid: uuid) else { return nil }
        return downloadableMediaTokenContext(dataSource: dataSource, pagePosition: pagePosition)
    }

    private func collectionTokenContext(
        uuid: UUID,
        pagePosition: PlayerPagePosition
    ) -> PlayerTokenContext? {
        dataSource(uuid: uuid)?.collectionTokenContext(pagePosition: pagePosition)
    }

    private func downloadableMediaTokenContext(
        dataSource: PlayerTokenPagingDataSource,
        pagePosition: PlayerPagePosition
    ) -> PlayerTokenContext? {
        guard let context = dataSource.collectionTokenContext(pagePosition: pagePosition),
              MobileCollectionCatalog.hasDownloadableMediaDescriptor(specificCollectionId: context.collectionId) else {
            return nil
        }
        return context
    }

    func markViewed(uuid: UUID, pagePosition: PlayerPagePosition) -> MobileViewingProgress? {
        guard let progress = dataSource(uuid: uuid)?.progress(pagePosition: pagePosition) else { return nil }
        updateViewingSessionTracker(uuid: uuid) { tracker in
            tracker.markViewed(progress)
        }
        return progress
    }

    func progress(uuid: UUID, pagePosition: PlayerPagePosition) -> MobileViewingProgress? {
        dataSource(uuid: uuid)?.progress(pagePosition: pagePosition)
    }

    func downloadedFileShareItem(uuid: UUID, pagePosition: PlayerPagePosition) -> MobilePlayerFileShareItem? {
        guard let dataSource = dataSource(uuid: uuid),
              let context = downloadableMediaTokenContext(dataSource: dataSource, pagePosition: pagePosition),
              let descriptor = MobileCollectionCatalog.downloadableMediaDescriptor(
                specificCollectionId: context.collectionId,
                tokenIndex: context.tokenIndex
              ) else {
            return nil
        }

        let releaseFile = DownloadableMediaCache.shared.retainFile(for: descriptor)
        guard let fileURL = DownloadableMediaCache.shared.localFileURL(for: descriptor) else {
            releaseFile()
            return nil
        }
        let token = dataSource.getToken(pagePosition: pagePosition)
        return MobilePlayerFileShareItem(
            fileURL: fileURL,
            previewTitle: MobilePlayerFileShareItem.previewTitle(
                for: token,
                progressText: dataSource.pageLabel(pagePosition: pagePosition)
                    ?? Strings.pagePosition(current: context.tokenIndex + 1, total: context.tokenCount)
            ),
            releaseFile: releaseFile
        ) {
            DownloadableMediaCache.shared.cachedDecodedImage(for: descriptor)
        }
    }

    private func suppressContinueViewingUntilMovementAfterRestart(uuid: UUID) {
        let collectionId: String?
        if let pagePosition = displays[uuid]?.getCurrentPagePosition() {
            collectionId = dataSource(uuid: uuid)?.collectionTokenContext(pagePosition: pagePosition)?.collectionId
        } else {
            collectionId = nil
        }

        updateViewingSessionTracker(uuid: uuid) { tracker in
            tracker.beginRestart(collectionId: collectionId)
        }
    }

    func startPagePosition(uuid: UUID) -> PlayerPagePosition {
        dataSource(uuid: uuid)?.pagePosition(forTokenIndex: 0) ?? .initial
    }

    private func dataSource(uuid: UUID) -> PlayerTokenPagingDataSource? {
        guard let initialConfig = initialConfigs[uuid] else { return nil }
        if let dataSource = tokensDataSources[uuid] {
            return dataSource
        }

        let newDataSource = PlayerTokenPagingDataSource(
            initialCollectionId: initialConfig.initialItemId,
            specificInitialToken: initialConfig.specificToken,
            initialTokenId: initialConfig.initialTokenId,
            widgetTokenInsertion: initialConfig.widgetTokenInsertion
        )
        tokensDataSources[uuid] = newDataSource
        return newDataSource
    }

    private func viewingSessionTracker(uuid: UUID) -> PlayerViewingSessionTracker {
        if let tracker = viewingSessionTrackers[uuid] {
            return tracker
        }

        let tracker = PlayerViewingSessionTracker(
            continueViewingCollectionId: initialConfigs[uuid]?.continueViewingCollectionId,
            trackingMode: initialConfigs[uuid]?.trackingMode ?? .updateContinueViewing
        )
        viewingSessionTrackers[uuid] = tracker
        return tracker
    }

    private func updateViewingSessionTracker<T>(
        uuid: UUID,
        _ update: (inout PlayerViewingSessionTracker) -> T
    ) -> T {
        var tracker = viewingSessionTracker(uuid: uuid)
        let result = update(&tracker)
        viewingSessionTrackers[uuid] = tracker
        return result
    }

}

enum MobilePlayerPrewarmer {

    static func scheduleAfterLaunch(continueViewingProgress: MobileViewingProgress?, initialCollectionIds: [String]) {
        AutoReloadingWebView.scheduleFirstUsePrewarm()
        PlayerTokenPrewarmer.scheduleAfterLaunch(
            continueViewingProgress: continueViewingProgress,
            initialCollectionIds: initialCollectionIds
        )
    }

    static func preparedConfig(
        initialItemId: String?,
        initialTokenId: String? = nil,
        continueViewingCollectionId: String?,
        trackingMode: PlayerViewingSessionTrackingMode = .updateContinueViewing,
        widgetTokenInsertion: PlayerWidgetTokenInsertion? = nil
    ) -> MobilePlayerConfig {
        var config = MobilePlayerConfig(
            initialItemId: initialItemId,
            initialTokenId: initialTokenId,
            continueViewingCollectionId: continueViewingCollectionId,
            trackingMode: trackingMode,
            widgetTokenInsertion: widgetTokenInsertion
        )
        if widgetTokenInsertion == nil {
            config.specificToken = PlayerTokenPrewarmer.preparedToken(
                initialCollectionId: initialItemId,
                initialTokenId: initialTokenId
            )
        }
        return config
    }
}
