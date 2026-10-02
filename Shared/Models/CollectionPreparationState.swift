import Foundation
import Observation

nonisolated struct CollectionOpeningDestination: Identifiable, Equatable, Sendable {
    enum Layout: Equatable, Sendable {
        case browser(columnCount: Int)
        case artwork
    }

    let id = UUID()
    let collectionId: String
    let title: String
    let itemCount: Int
    let uniformAspectRatio: AspectRatio?
    let layout: Layout
    private(set) var initialTokenIndex: Int

    init(
        collectionId: String,
        opensToken: Bool = false,
        initialTokenIndex: Int? = nil
    ) {
        let item = SuggestedItemsService.item(id: collectionId)
        self.collectionId = collectionId
        title = item?.name ?? Strings.nftPlayer
        itemCount = max(CollectionCatalog.tokenCount(specificCollectionId: collectionId), 0)
        self.initialTokenIndex = min(max(initialTokenIndex ?? 0, 0), max(itemCount - 1, 0))
        if itemCount > 0, item?.hasUniformAspectRatio == true {
            uniformAspectRatio = item?.aspectRatio
        } else {
            uniformAspectRatio = nil
        }
#if os(iOS) || os(macOS)
        if !opensToken, PlayerCollectionBrowserSupport.isAvailable(forCollectionId: collectionId) {
#if os(macOS)
            layout = .browser(columnCount: CollectionCatalog.desktopCollectionBrowseColumnCount(
                specificCollectionId: collectionId
            ))
#else
            layout = .browser(columnCount: MobilePlayerBrowserLayout.defaultColumnCount)
#endif
        } else {
            layout = .artwork
        }
#else
        layout = .artwork
#endif
    }

    func withInitialTokenIndex(_ index: Int) -> Self {
        var destination = self
        destination.initialTokenIndex = min(max(index, 0), max(itemCount - 1, 0))
        return destination
    }

    func placeholderFrames(
        viewportSize: CGSize,
        displayScale: CGFloat,
        topContentInset: CGFloat = 0,
        bottomContentInset: CGFloat = 0
    ) -> [CGRect] {
        guard itemCount > 0,
              let uniformAspectRatio,
              viewportSize.width.isFinite, viewportSize.width > 0,
              viewportSize.height.isFinite, viewportSize.height > 0 else {
            return []
        }
        switch layout {
        case .artwork:
            let size = uniformAspectRatio.size
            let scale = min(viewportSize.width / size.width, viewportSize.height / size.height)
            let fittedSize = CGSize(width: size.width * scale, height: size.height * scale)
            return [CGRect(
                x: (viewportSize.width - fittedSize.width) / 2,
                y: (viewportSize.height - fittedSize.height) / 2,
                width: fittedSize.width,
                height: fittedSize.height
            )]
        case let .browser(columnCount):
#if os(iOS) || os(macOS)
            guard let browserLayout = MobilePlayerBrowserLayout(
                viewportSize: viewportSize,
                displayScale: displayScale,
                topContentInset: topContentInset,
                bottomContentInset: bottomContentInset,
                aspectProfile: MobilePlayerBrowserAspectProfile(
                    itemCount: itemCount,
                    uniformImageSize: uniformAspectRatio.size,
                    columnCount: columnCount
                )
            ), let anchor = browserLayout.itemFrame(at: initialTokenIndex),
               let firstFrame = browserLayout.itemFrame(at: 0),
               let lastFrame = browserLayout.itemFrame(at: itemCount - 1) else { return [] }
            let maximumOffset = max(browserLayout.contentSize.height - viewportSize.height, 0)
            let lastRowFirstIndex = ((itemCount - 1) / browserLayout.columnCount) * browserLayout.columnCount
            let previousRowFrame = browserLayout.itemFrame(at: lastRowFirstIndex - browserLayout.columnCount)
            let lastRowFocalEntryY = previousRowFrame.map { ($0.midY + lastFrame.midY) / 2 }
                ?? firstFrame.midY
            let focalGeometry = PlayerCollectionScrollFocalGeometry(
                minimumOffsetY: 0,
                maximumOffsetY: maximumOffset,
                viewportHeight: viewportSize.height,
                viewportCenterX: viewportSize.width / 2,
                firstItemCenter: CGPoint(x: firstFrame.midX, y: firstFrame.midY),
                lastItemCenter: CGPoint(x: lastFrame.midX, y: lastFrame.midY),
                lastRowFocalEntryY: lastRowFocalEntryY
            )
            let offset = focalGeometry?.contentOffsetY(anchoringFocalY: anchor.midY)
                ?? min(max(anchor.midY - viewportSize.height / 2, 0), maximumOffset)
            let viewport = CGRect(origin: CGPoint(x: 0, y: offset), size: viewportSize)
            return browserLayout.candidateItemIndices(intersecting: viewport).compactMap { index in
                guard let frame = browserLayout.itemFrame(at: index), frame.intersects(viewport) else {
                    return nil
                }
                return frame.offsetBy(dx: 0, dy: -offset)
            }
#else
            return []
#endif
        }
    }
}

@MainActor
@Observable
final class CollectionPreparationState {
    private(set) var isLoading = false
    var errorMessage: String?

    private var generation = 0
    private var task: Task<Void, Error>?
    private var retryAction: (@MainActor () -> Void)?

    func prepare(
        collectionId: String,
        operation: @escaping @MainActor (String) async throws -> Void = {
            try await CollectionCatalog.prepareCollection(collectionId: $0)
        },
        isCurrent: @MainActor () -> Bool,
        retry: @escaping @MainActor () -> Void
    ) async -> Bool {
        guard isCurrent(), !Task.isCancelled else { return false }
        cancel()
        let generation = generation
        isLoading = true
        let task = Task { try await operation(collectionId) }
        self.task = task
        do {
            try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
            guard self.generation == generation else { return false }
            self.task = nil
            isLoading = false
            return isCurrent() && !Task.isCancelled
        } catch {
            guard self.generation == generation else { return false }
            self.task = nil
            isLoading = false
            guard isCurrent(), !Task.isCancelled, !(error is CancellationError) else { return false }
            errorMessage = error.localizedDescription
            retryAction = retry
            return false
        }
    }

    func retry() {
        let action = retryAction
        cancel()
        action?()
    }

    func cancel() {
        generation &+= 1
        task?.cancel()
        task = nil
        isLoading = false
        errorMessage = nil
        retryAction = nil
    }
}
