// ∅ 2026 lil org

import QuartzCore
import UIKit
import os

enum MobilePlayerCollectionBrowserDisplayPreparationResult: Equatable {
    case prepared
    case superseded
    case unavailable
}

final class VerticalCollectionBrowserViewController: UIViewController,
    UICollectionViewDataSource,
    UICollectionViewDelegate {

    private struct PreparedTransition {
        let preparation: PlayerCollectionBrowsePreparation
        let contentOffset: CGPoint
        let layoutSize: CGSize
        let layoutDisplayScale: CGFloat
        let layoutWindowSafeAreaInsets: UIEdgeInsets
        let verticalContentOffsetRange: ClosedRange<CGFloat>
        let browseSnapshot: PlayerCollectionBrowseSnapshot?
        let scrollCoordinatorSnapshot:
            MobilePlayerCollectionBrowserScrollCoordinator.Snapshot
        let imagePipelineSnapshot:
            MobilePlayerCollectionBrowserImagePipeline.Snapshot
        let layoutAspectState: MobilePlayerCollectionBrowserLayoutAspectState
    }

    private struct WindowSafeAreaState {
        let insets: UIEdgeInsets
    }

    private struct LayoutAspectSample {
        let index: Int
        let size: CGSize
        let usesNativeMetalCardCornerMask: Bool
    }

    private struct WindowSafeAreaLayoutUpdate {
        let insetsToCapture: UIEdgeInsets?
        let clearsPendingRefresh: Bool
        let requiresLayoutRefresh: Bool
    }

    private static let cellReuseIdentifier = "MobilePlayerCollectionBrowserCell"
    private static let boundaryEpsilon: CGFloat = 0.75
    private static let verticalContentMargin: CGFloat = 0
    private static let signposter = OSSignposter(
        subsystem: Bundle.main.bundleIdentifier ?? "org.lil.nft-player",
        category: "CollectionBrowserScroll"
    )

    private let playbackSession: MobilePlaybackSession

    var onFocusedPagePosition: ((PlayerPagePosition) -> Void)?
    var onSettledPagePosition: ((PlayerPagePosition, Bool) -> Bool)?
    var onSelection: ((MobilePlayerBrowserTransitionSelection) -> Bool)?
    var onImmediateSelection: ((PlayerPagePosition, @escaping () -> Void) -> Bool)?
#if DEBUG
    typealias ThumbnailWindowMetrics =
        MobilePlayerCollectionBrowserImagePipeline.ThumbnailWindowMetrics

    var thumbnailWindowMetrics: ThumbnailWindowMetrics {
        imagePipeline.thumbnailWindowMetrics
    }
#endif

    private let browserCollectionLayout = MobilePlayerCollectionBrowserLayout()
    private let imagePipeline = MobilePlayerCollectionBrowserImagePipeline()
    private let scrollCoordinator =
        MobilePlayerCollectionBrowserScrollCoordinator()
    private let gridModeCoordinator:
        MobilePlayerCollectionBrowserGridModeCoordinator
    private lazy var collectionView: MobilePlayerCollectionBrowserCollectionView = {
        let collectionView = MobilePlayerCollectionBrowserCollectionView(
            frame: .zero,
            collectionViewLayout: browserCollectionLayout
        )
        collectionView.backgroundColor = .clear
        collectionView.isOpaque = false
        collectionView.alwaysBounceVertical = true
        collectionView.alwaysBounceHorizontal = false
        collectionView.showsVerticalScrollIndicator = false
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.keyboardDismissMode = .none
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.scrollsToTop = false
        collectionView.accessibilityIdentifier = "MobilePlayerCollectionBrowser"
        collectionView.register(
            MobilePlayerCollectionBrowserCell.self,
            forCellWithReuseIdentifier: Self.cellReuseIdentifier
        )
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.onWillAccessibilityScroll = { [weak self] in
            guard let self else {
                return .init(
                    interruptedGridModeSettle: false,
                    wasScrollMotionActive: false
                )
            }
            let wasScrollMotionActive = self.isScrollMotionActive
            let interrupted = self.gridModeCoordinator
                .finalizeInterruptibleSettle()
            self.beginScrollMotion()
            return .init(
                interruptedGridModeSettle: interrupted,
                wasScrollMotionActive: wasScrollMotionActive
            )
        }
        collectionView.onAccessibilityScrollResult = {
            [weak self] succeeded, attempt in
            guard let self else { return }
            if succeeded {
                self.gridModeCoordinator.discardTransitionCover()
                self.scheduleScrollMotionAnimationTimeout()
                return
            }
            if !attempt.wasScrollMotionActive {
                self.endScrollMotion()
                self.prepareCurrentImageWindowIfPossible()
                self.resumeVisibleBrowserImageLoadsIfNeeded()
                self.gridModeCoordinator.scheduleGeometryPrewarmIfPossible()
            }
            if attempt.interruptedGridModeSettle {
                self.gridModeCoordinator
                    .settleAfterImmediateOffsetIfPossible()
            }
        }
        collectionView.contentOffsetTarget = { [weak self] requestedContentOffset, animated in
            self?.gridModeCoordinator.contentOffsetTarget(
                for: requestedContentOffset,
                animated: animated
            ) ?? (requestedContentOffset, false)
        }
        collectionView.onDidApplyImmediateContentOffset = { [weak self] in
            self?.gridModeCoordinator.settleAfterImmediateOffsetIfPossible()
        }
        return collectionView
    }()
    private var browseSnapshot: PlayerCollectionBrowseSnapshot?
    private var publicationState: PlayerCollectionScrollPublicationState? {
        get { scrollCoordinator.publicationState }
        set { scrollCoordinator.publicationState = newValue }
    }
    private var hasFinishedInitialPositioning: Bool {
        get { scrollCoordinator.hasFinishedInitialPositioning }
        set { scrollCoordinator.hasFinishedInitialPositioning = newValue }
    }
    private var isActive: Bool {
        get { scrollCoordinator.isActive }
        set {
            scrollCoordinator.setActive(newValue)
            imagePipeline.setActive(newValue)
        }
    }
    private var isViewVisible: Bool {
        get { imagePipeline.isVisible }
        set { imagePipeline.setVisible(newValue) }
    }
    private var isApplyingPosition: Bool {
        get { scrollCoordinator.isApplyingPosition }
        set { scrollCoordinator.setApplyingPosition(newValue) }
    }
    private var lastLayoutSize = CGSize.zero
    private var lastLayoutDisplayScale: CGFloat = 0
    private var focusedTokenIndex: Int? {
        get { scrollCoordinator.focusedTokenIndex }
        set { scrollCoordinator.focusedTokenIndex = newValue }
    }
    private var forcedFocusedTokenIndex: Int? {
        get { scrollCoordinator.forcedFocusedTokenIndex }
        set { scrollCoordinator.forcedFocusedTokenIndex = newValue }
    }
    private var retainedFocusFocalBias: PlayerCollectionScrollFocalBias? {
        get { scrollCoordinator.retainedFocusFocalBias }
        set { scrollCoordinator.retainedFocusFocalBias = newValue }
    }
    private var lastEmittedFocusedTokenIndex: Int? {
        get { scrollCoordinator.lastEmittedFocusedTokenIndex }
        set { scrollCoordinator.lastEmittedFocusedTokenIndex = newValue }
    }
    private var lastScrollOffsetY: CGFloat? {
        get { scrollCoordinator.lastScrollOffsetY }
        set { scrollCoordinator.lastScrollOffsetY = newValue }
    }
    private var dragStartContentOffsetY: CGFloat? {
        get { scrollCoordinator.dragStartContentOffsetY }
        set { scrollCoordinator.dragStartContentOffsetY = newValue }
    }
    private var needsWindowSafeAreaRefresh = false
    private var isScrollMotionActive: Bool {
        scrollCoordinator.isScrollMotionActive
    }
    private(set) var lastPrefetchDirection:
        DownloadableMediaCache.PrefetchDirection {
        get { scrollCoordinator.lastPrefetchDirection }
        set { scrollCoordinator.setPrefetchDirection(newValue) }
    }
    private var preparedTransition: PreparedTransition?
    private var layoutAspectState = MobilePlayerCollectionBrowserLayoutAspectState(
        aspectProfile: MobilePlayerBrowserAspectProfile(
            itemCount: 0,
            uniformImageSize: CGSize(width: 1, height: 1)
        ),
        fallbackSpec: PlayerMediaPlaceholderSpec(
            aspectSize: CGSize(width: 1, height: 1)
        )
    )
    private var layoutWindowSafeAreaInsets = UIEdgeInsets.zero
    private var hasCapturedLayoutWindowSafeAreaInsets = false
    private var scrollSessionSignpost: OSSignpostIntervalState?

    private var configuredColumnCount: Int {
        browserCollectionLayout.browserLayout?.columnCount ?? 0
    }

    private var configuredPrefetchStride: Int {
        browserCollectionLayout.browserLayout?.prefetchStride
            ?? MobilePlayerBrowserLayout.defaultColumnCount
    }

    private var requiredImageQuality: CollectionBrowseImageQuality {
        gridMode.requiredImageQuality
    }

    private var browserImageDecodeVariant: DownloadableMediaImageDecodeVariant {
        guard let browserLayout = browserCollectionLayout.browserLayout else {
            return .full
        }
        return MobilePlayerCollectionBrowserGridImageDecodeVariant.resolve(
            for: browserLayout,
            displayScale: currentLayoutDisplayScale
        )
    }

    init(
        playbackSession: MobilePlaybackSession,
        gridModeCommitSnapshotFactory: @escaping (UIView) -> UIView? = { view in
            view.resizableSnapshotView(
                from: view.bounds,
                afterScreenUpdates: false,
                withCapInsets: .zero
            )
        },
        gridTransitionFrameDriver:
            (any GridTransitionFrameDriving)? = nil
    ) {
        self.playbackSession = playbackSession
        self.gridModeCoordinator =
            MobilePlayerCollectionBrowserGridModeCoordinator(
                commitSnapshotFactory: gridModeCommitSnapshotFactory,
                frameDriver: gridTransitionFrameDriver
            )
        super.init(nibName: nil, bundle: nil)
        imagePipeline.configure(contentAccess: .init(
            visibleIndexPaths: { [weak self] in
                self?.collectionView.indexPathsForVisibleItems ?? []
            },
            cell: { [weak self] indexPath in
                self?.collectionView.cellForItem(at: indexPath)
                    as? MobilePlayerCollectionBrowserCell
            },
            visibleCells: { [weak self] in
                self?.visibleBrowserCells ?? []
            },
            viewportRenderCells: { [weak self] tokenIndex in
                self?.gridModeCoordinator.viewportRenderCells(at: tokenIndex) ?? []
            },
            collectionID: { [weak self] in
                self?.browseSnapshot?.collectionId
            },
            requiredImageQuality: { [weak self] in
                self?.requiredImageQuality ?? .large
            },
            imageDecodeVariant: { [weak self] in
                self?.browserImageDecodeVariant ?? .full
            },
            baseColumnCount: { [weak self] in
                self?.gridMode.columnCount ?? 0
            },
            isRendererActive: { [weak self] in
                self?.gridModeCoordinator.isRendererActive == true
            },
            isApplyingPosition: { [weak self] in
                self?.isApplyingPosition == true
            },
            isPreparedTransitionActive: { [weak self] in
                self?.preparedTransition != nil
            },
            isForegroundActive: { [weak self] in
                self?.collectionView.window?.windowScene?.activationState
                    == .foregroundActive
            },
            projectedTokenRange: { [weak self] tokenIndex, direction, distance in
                self?.projectedBrowserTokenRange(
                    around: tokenIndex,
                    direction: direction,
                    refreshDistance: distance
                )
            },
            prepareThumbnailWindow: { [weak self] preparation in
                guard let self else { return }
                self.playbackSession.prepareCollectionBrowseThumbnailWindow(
                    centeredAt: preparation.tokenIndex,
                    direction: preparation.direction,
                    prefetchStride: preparation.prefetchStride,
                    columnCount: preparation.columnCount,
                    quality: preparation.quality,
                    requiredTokenRange: preparation.requiredTokenRange,
                    visibleTokenRange: preparation.visibleTokenRange,
                    isFileOnly: preparation.isFileOnly,
                    decodeVariant: preparation.decodeVariant,
                    displayedHigherQualityThumbnailTokenIndices:
                        preparation
                            .displayedHigherQualityThumbnailTokenIndices,
                    displayedLargeTokenIndices:
                        preparation.displayedLargeTokenIndices,
                    locallyAvailableLargeTokenIndices:
                        preparation.locallyAvailableLargeTokenIndices
                )
            }
        ))
        scrollCoordinator.configure(contentAccess: .init(
            pagePosition: { [weak self] tokenIndex in
                self?.browseSnapshot?.pagePosition(forTokenIndex: tokenIndex)
            },
            publishFocusedPagePosition: { [weak self] pagePosition in
                self?.onFocusedPagePosition?(pagePosition)
            },
            publishSettledPosition: { [weak self] publication in
                self?.publishSettledPagePosition(publication) == true
            },
            performScheduledScrollObservation: { [weak self] in
                self?.observeCurrentAnchor(
                    focusCadence: .continuous,
                    preparesThumbnailWindow: true,
                    forcesThumbnailWindow: false
                )
            },
            scrollMotionAnimationDidExpire: { [weak self] in
                self?.handleScrollMotionAnimationTimeout()
            }
        ))
    }

    private func configureGridModeCoordinator() {
        gridModeCoordinator.configure(
            collectionView: collectionView,
            viewportView: view,
            collectionLayout: browserCollectionLayout,
            scrollCoordinator: scrollCoordinator,
            imagePipeline: imagePipeline,
            rendererContentAccess: .init(
                configureCell: { [weak self] cell, indexPath, configuration in
                    self?.configureBrowserCell(
                        cell,
                        at: indexPath,
                        requiredImageQuality:
                            configuration.requiredImageQuality,
                        imageLoadPolicy: configuration.imageLoadPolicy,
                        allowsLocalLargeImageUpgrade:
                            configuration.allowsLocalLargeImageUpgrade,
                        imageDecodeVariant: configuration.imageDecodeVariant
                    )
                },
                contentIdentity: { [weak self] in
                    self?.browserContentIdentity(forTokenIndex: $0)
                },
                imageSources: { [weak self] in
                    self?.browseImageSources(forTokenIndex: $0)
                }
            ),
            currentState: { [unowned self] in
                .init(
                    browseSnapshot: browseSnapshot,
                    layoutAspectState: layoutAspectState,
                    isActive: isActive,
                    isViewVisible: isViewVisible,
                    isApplyingPosition: isApplyingPosition,
                    hasFinishedInitialPositioning:
                        hasFinishedInitialPositioning,
                    focusedTokenIndex: focusedTokenIndex,
                    forcedFocusedTokenIndex: forcedFocusedTokenIndex,
                    isScrollMotionActive: isScrollMotionActive,
                    needsWindowSafeAreaRefresh:
                        needsWindowSafeAreaRefresh,
                    hasPreparedTransition: preparedTransition != nil,
                    currentLayoutDisplayScale: currentLayoutDisplayScale,
                    layoutWindowSafeAreaInsets:
                        layoutWindowSafeAreaInsets
                )
            },
            layoutOperations: .init(
                makeLayoutAspectState: {
                    [unowned self] snapshot, columnCount,
                    focusedTokenIndex, aspectRatioProfile in
                    makeLayoutAspectState(
                        snapshot: snapshot,
                        columnCount: columnCount,
                        focusedTokenIndex: focusedTokenIndex,
                        aspectRatioProfile: aspectRatioProfile
                    )
                },
                makeLayoutFallbackSpec: {
                    [unowned self] snapshot, focusedTokenIndex in
                    makeLayoutFallbackSpec(
                        snapshot: snapshot,
                        focusedTokenIndex: focusedTokenIndex
                    )
                },
                makeLayoutAspectProfile: {
                    [unowned self] snapshot, columnCount,
                    aspectRatioProfile in
                    makeLayoutAspectProfile(
                        snapshot: snapshot,
                        columnCount: columnCount,
                        aspectRatioProfile: aspectRatioProfile
                    )
                },
                makeBrowserLayout: { [unowned self] aspectProfile in
                    makeBrowserLayout(aspectProfile: aspectProfile)
                },
                installCollectionLayout: { [unowned self] layout in
                    installCollectionLayout(layout)
                },
                centerContent: { [unowned self] tokenIndex in
                    centerContent(on: tokenIndex)
                },
                currentAnchorTokenIndex: { [unowned self] in
                    currentAnchorTokenIndex()
                },
                currentFocalPoint: { [unowned self] in
                    currentFocalPoint()
                },
                retainFocusedTokenIndex: { [unowned self] tokenIndex in
                    retainFocusedTokenIndex(tokenIndex)
                }
            ),
            browserEffects: .init(
                setBrowseSnapshot: { [weak self] snapshot in
                    self?.browseSnapshot = snapshot
                },
                setLayoutAspectState: { [weak self] state in
                    self?.layoutAspectState = state
                },
                updateLayoutAspectProfile: {
                    [weak self] snapshot, focusedTokenIndex, columnCount in
                    self?.updateLayoutAspectProfile(
                        snapshot: snapshot,
                        focusedTokenIndex: focusedTokenIndex,
                        columnCount: columnCount
                    )
                },
                configureCollectionLayout: { [weak self] in
                    self?.configureCollectionLayout()
                },
                endScrollMotionAndResetDragState: { [weak self] in
                    self?.endScrollMotionAndResetDragState()
                },
                settleCurrentPosition: { [weak self] in
                    self?.settleCurrentPosition()
                },
                prepareCurrentImageWindowIfPossible: { [weak self] in
                    self?.prepareCurrentImageWindowIfPossible()
                },
                settleAfterApplyingPendingWindowSafeAreaRefresh: {
                    [weak self] in
                    self?.settleAfterApplyingPendingWindowSafeAreaRefresh()
                },
                reloadVisibleCells: { [weak self] in
                    self?.reloadVisibleCells()
                },
                browseImageSources: { [weak self] tokenIndex in
                    self?.browseImageSources(forTokenIndex: tokenIndex)
                }
            )
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    isolated deinit {
        endScrollSessionSignpost()
        NotificationCenter.default.removeObserver(self)
        gridModeCoordinator.invalidate()
        scrollCoordinator.invalidate()
        imagePipeline.invalidate()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.isOpaque = false
        view.clipsToBounds = true

        registerForTraitChanges([UITraitDisplayScale.self]) {
            (controller: VerticalCollectionBrowserViewController, _) in
            controller.view.setNeedsLayout()
        }

        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        configureGridModeCoordinator()

        reloadBrowseSnapshot(resetPublicationState: true)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sceneDidEnterBackground(_:)),
            name: UIScene.didEnterBackgroundNotification,
            object: nil,
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sceneDidActivate(_:)),
            name: UIScene.didActivateNotification,
            object: nil,
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(downloadableMediaCacheFileAvailabilityDidChange(_:)),
            name: .downloadableMediaCacheFileAvailabilityDidChange,
            object: nil,
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(downloadableMediaCacheDecodedImageDidBecomeAvailable(_:)),
            name: .downloadableMediaCacheDecodedImageDidBecomeAvailable,
            object: nil,
        )
    }

    @objc private func sceneDidEnterBackground(_ notification: Notification) {
        guard let windowScene = notification.object as? UIWindowScene,
              let currentWindowScene = collectionView.window?.windowScene,
              windowScene === currentWindowScene else {
            return
        }
        gridModeCoordinator.interruptInteractionIfNeeded()
        endScrollMotionAndResetDragState()
        flushSettledPosition()
        gridModeCoordinator.cancelGeometryPrewarming()
    }

    @objc private func sceneDidActivate(_ notification: Notification) {
        guard let windowScene = notification.object as? UIWindowScene,
              let currentWindowScene = collectionView.window?.windowScene,
              windowScene === currentWindowScene else {
            return
        }
        resumeVisibleBrowserImageLoadsIfNeeded()
        prepareCurrentImageWindowIfPossible()
        gridModeCoordinator.scheduleGeometryPrewarmIfPossible()
    }

    @objc private func downloadableMediaCacheFileAvailabilityDidChange(
        _ notification: Notification
    ) {
        refreshVisibleCachedImagesIfNeeded(notification: notification)
    }

    @objc private func downloadableMediaCacheDecodedImageDidBecomeAvailable(
        _ notification: Notification
    ) {
        imagePipeline.handleDecodedImageNotification(notification)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        let viewportSize = view.bounds.size
        let sizeChanged = lastLayoutSize != .zero && lastLayoutSize != viewportSize
        let displayScale = currentLayoutDisplayScale
        let displayScaleChanged = lastLayoutDisplayScale > 0
            && lastLayoutDisplayScale != displayScale
        let previousImageDecodeVariant = browserCollectionLayout.browserLayout
            .map {
                MobilePlayerCollectionBrowserGridImageDecodeVariant.resolve(
                    for: $0,
                    displayScale: lastLayoutDisplayScale > 0
                        ? lastLayoutDisplayScale
                        : displayScale
                )
            } ?? .full
        let windowSafeAreaLayoutUpdate = resolveWindowSafeAreaLayoutUpdate(
            state: currentWindowSafeAreaState,
            sizeChanged: sizeChanged
        )
        let geometryChanged = sizeChanged || displayScaleChanged
            || windowSafeAreaLayoutUpdate.requiresLayoutRefresh
        let interruptedGridModeAnchorTokenIndex: Int?
        switch gridModeCoordinator.prepareForGeometryChange(geometryChanged) {
        case let .ready(anchorTokenIndex):
            interruptedGridModeAnchorTokenIndex = anchorTokenIndex
        case .retryAfterInteractionFinishes:
            view.setNeedsLayout()
            return
        }
        let previousLayoutWindowSafeAreaInsets = layoutWindowSafeAreaInsets
        let previousContentOffset = collectionView.contentOffset
        let previousVerticalContentOffsetRange = verticalContentOffsetRange

        if let insets = windowSafeAreaLayoutUpdate.insetsToCapture {
            captureLayoutWindowSafeAreaInsets(insets)
        }
        if windowSafeAreaLayoutUpdate.clearsPendingRefresh {
            needsWindowSafeAreaRefresh = false
        }
        let transition = MobilePlayerBrowserLayout.viewportTransition(
            previousViewportSize: lastLayoutSize,
            viewportSize: viewportSize,
            needsGeometryRefresh:
                displayScaleChanged
                    || windowSafeAreaLayoutUpdate.requiresLayoutRefresh,
            displayScale: displayScale,
            topContentInset:
                Self.verticalContentMargin + layoutWindowSafeAreaInsets.top,
            bottomContentInset:
                Self.verticalContentMargin + layoutWindowSafeAreaInsets.bottom,
            aspectProfile: layoutAspectState.aspectProfile,
            forcedTokenIndex: forcedFocusedTokenIndex,
            interactionAnchorTokenIndex:
                interruptedGridModeAnchorTokenIndex,
            focusedTokenIndex: focusedTokenIndex
        )
        let wasApplyingPosition = isApplyingPosition
        if transition.needsLayout {
            isApplyingPosition = true
            if let browserLayout = transition.layout {
                installCollectionLayout(browserLayout)
            }
            collectionView.layoutIfNeeded()
        }

        if transition.geometryChanged,
           !transition.needsInitialLayout {
            if sizeChanged || displayScaleChanged,
               let retainedFocus = transition.retainedFocusTokenIndex {
                centerContent(on: retainedFocus)
                retainFocusedTokenIndex(retainedFocus)
                focusedTokenIndex = retainedFocus
            } else if windowSafeAreaLayoutUpdate.requiresLayoutRefresh {
                restoreContentPositionAfterSafeAreaChange(
                    previousContentOffset: previousContentOffset,
                    previousTopContentInset:
                        previousLayoutWindowSafeAreaInsets.top,
                    previousVerticalContentOffsetRange:
                        previousVerticalContentOffsetRange,
                    retainedFocusTokenIndex:
                        transition.retainedFocusTokenIndex
                )
            }
        }
        if transition.needsLayout {
            lastScrollOffsetY = collectionView.contentOffset.y
        }
        isApplyingPosition = wasApplyingPosition
        lastLayoutSize = viewportSize
        lastLayoutDisplayScale = displayScale

        guard isActive else { return }
        if previousImageDecodeVariant != browserImageDecodeVariant {
            imagePipeline.resetThumbnailWindow()
            reloadVisibleCells()
        }
        let hadFinishedInitialPositioning = hasFinishedInitialPositioning
        performInitialPositioningIfNeeded()
        if hadFinishedInitialPositioning,
           transition.geometryChanged,
           !isApplyingPosition {
            settleCurrentPosition()
        } else if windowSafeAreaLayoutUpdate.clearsPendingRefresh {
            gridModeCoordinator.scheduleGeometryPrewarmIfPossible()
        }
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        gridModeCoordinator.cancelGeometryPrewarming()
        needsWindowSafeAreaRefresh = true
        view.setNeedsLayout()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        isViewVisible = true
        resumeVisibleBrowserImageLoadsIfNeeded()
        prepareCurrentImageWindowIfPossible()
        gridModeCoordinator.scheduleGeometryPrewarmIfPossible()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        isViewVisible = false
        gridModeCoordinator.interruptInteractionIfNeeded()
        endScrollMotionAndResetDragState()
        flushSettledPosition()
        gridModeCoordinator.cancelGeometryPrewarming()
    }

    var currentPagePosition: PlayerPagePosition? {
        guard let browseSnapshot,
              let tokenIndex = forcedFocusedTokenIndex ?? focusedTokenIndex else {
            return nil
        }
        return browseSnapshot.pagePosition(forTokenIndex: tokenIndex)
    }

    var gridMode: MobileCollectionBrowserGridMode {
        gridModeCoordinator.gridMode
    }

    func makeGridModeMenu() -> UIMenu {
        gridModeCoordinator.makeMenu()
    }

    @discardableResult
    func setGridMode(_ gridMode: MobileCollectionBrowserGridMode) -> Bool {
        gridModeCoordinator.setGridMode(gridMode)
    }
    func setActive(_ active: Bool) {
        if active {
            loadViewIfNeeded()
        }
        guard isActive != active else {
            if active {
                performInitialPositioningIfNeeded()
            }
            return
        }
        gridModeCoordinator.interruptInteractionIfNeeded()

        if active,
           let preparation = preparedTransition?.preparation,
           !finalizePreparedDisplay(preparation) {
            return
        }

        if !active {
            gridModeCoordinator.cancelGeometryPrewarming()
            flushSettledPosition()
            endScrollMotionAndResetDragState()
            cancelScheduledScrollUpdate()
            cancelPendingFocusPublication(resetLastPublicationTime: true)
            imagePipeline.resetThumbnailWindow()
            imagePipeline.cancelVisibleCellImageLoads()
        }

        isActive = active
        collectionView.isScrollEnabled = active
        collectionView.isUserInteractionEnabled = active
        collectionView.scrollsToTop = active
        if active {
            reloadBrowseSnapshot(
                resetPublicationState: browseSnapshot == nil
            )
            reloadVisibleCells()
            performInitialPositioningIfNeeded()
            if hasFinishedInitialPositioning {
                observeCurrentAnchor(
                    focusCadence: .immediate,
                    preparesThumbnailWindow: true,
                    forcesThumbnailWindow: true
                )
                publishSettledTokenIfNeeded()
            }
            gridModeCoordinator.scheduleGeometryPrewarmIfPossible()
        }
    }

    func prepareForDisplay(
        using preparation: PlayerCollectionBrowsePreparation,
        forcePosition: Bool = false,
        publishWhenStable: Bool,
        completion: @escaping @MainActor (
            MobilePlayerCollectionBrowserDisplayPreparationResult
        ) -> Void
    ) {
        loadViewIfNeeded()
        gridModeCoordinator.interruptInteractionIfNeeded()
        let generation = scrollCoordinator.beginPositioning()
        guard isValid(preparation) else {
            isApplyingPosition = false
            cancelPreparedTransition()
            completion(.unavailable)
            return
        }
        endScrollMotionAndResetDragState()

        if let preparedTransition,
           preparedTransition.preparation != preparation {
            restorePreparedTransition(preparedTransition)
        }
        if preparedTransition == nil {
            preparedTransition = makePreparedTransition(for: preparation)
        }

        isApplyingPosition = true
        let snapshotChanged = applyBrowseSnapshotIfNeeded(
            preparation.snapshot,
            sampledAround: preparation.focusedTokenIndex
        )

        scrollCoordinator.beginPublicationPositioning(
            at: preparation.focusedTokenIndex,
            snapshotChanged: snapshotChanged
        )

        if forcePosition
            || snapshotChanged
            || !isTokenFullyVisible(preparation.focusedTokenIndex) {
            centerContent(on: preparation.focusedTokenIndex)
        }
        retainFocusedTokenIndex(preparation.focusedTokenIndex)
        focusedTokenIndex = preparation.focusedTokenIndex
        collectionView.layoutIfNeeded()

        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else {
                completion(.superseded)
                return
            }
            guard self.scrollCoordinator
                .isCurrentPositioningGeneration(generation) else {
                completion(.superseded)
                return
            }

            self.collectionView.layoutIfNeeded()
            self.scrollCoordinator.finishPositioning()
            self.resumeVisibleBrowserImageLoadsIfNeeded()
            self.scrollCoordinator.observe(
                tokenIndex: preparation.focusedTokenIndex,
                focusCadence: .immediate
            )
            if publishWhenStable, self.isActive {
                self.publishSettledTokenIfNeeded()
            }
            self.prepareThumbnailWindow(
                around: preparation.focusedTokenIndex,
                direction: self.lastPrefetchDirection,
                force: true
            )
            if self.isActive {
                self.preparedTransition = nil
            }
            self.gridModeCoordinator.scheduleGeometryPrewarmIfPossible()
            completion(.prepared)
        }
    }

    func canCommitPreparedDisplay(
        _ preparation: PlayerCollectionBrowsePreparation
    ) -> Bool {
        !isActive
            && !isApplyingPosition
            && browseSnapshot == preparation.snapshot
            && preparedTransition?.preparation == preparation
    }

    func commitPreparedDisplay(
        _ preparation: PlayerCollectionBrowsePreparation
    ) {
        assert(canCommitPreparedDisplay(preparation))
        preparedTransition = nil
    }

    @discardableResult
    func finalizePreparedDisplay(
        _ preparation: PlayerCollectionBrowsePreparation
    ) -> Bool {
        guard browseSnapshot == preparation.snapshot else { return false }
        guard let preparedTransition else { return true }
        guard preparedTransition.preparation == preparation,
              playbackSession.collectionBrowseSnapshot() == preparation.snapshot else {
            return false
        }
        self.preparedTransition = nil
        return true
    }

    func cancelPendingDisplayPreparation() {
        scrollCoordinator.cancelPositioning()
        cancelPreparedTransition()
    }

    func canSelectItem(at location: CGPoint, in coordinateView: UIView) -> Bool {
        guard isActive, !gridModeCoordinator.hasInteractionState else {
            return false
        }
        let point = collectionView.convert(location, from: coordinateView)
        guard let indexPath = collectionView.indexPathForItem(at: point) else {
            return false
        }
        return canSelectBrowserCell(at: indexPath.item)
    }

    private func canSelectBrowserCell(at tokenIndex: Int) -> Bool {
        guard !gridModeCoordinator.blocksSelection,
              let identity = browserContentIdentity(
            forTokenIndex: tokenIndex
        ),
              let cell = collectionView.cellForItem(
                  at: IndexPath(item: tokenIndex, section: 0)
              ) as? MobilePlayerCollectionBrowserCell else {
            return false
        }
        return cell.canSelect(representing: identity)
    }

    func preparedTransitionSelection(
        for pagePosition: PlayerPagePosition
    ) -> MobilePlayerBrowserTransitionSelection? {
        guard let preparation = playbackSession.prepareCollectionBrowse(
            containing: pagePosition
        ) else {
            return nil
        }
        return preparedTransitionSelection(using: preparation)
    }

    func preparedTransitionSelection(
        using preparation: PlayerCollectionBrowsePreparation
    ) -> MobilePlayerBrowserTransitionSelection? {
        loadViewIfNeeded()
        gridModeCoordinator.interruptInteractionIfNeeded()
        guard isValid(preparation) else { return nil }
        endScrollMotionAndResetDragState()

        if let preparedTransition,
           preparedTransition.preparation != preparation {
            restorePreparedTransition(preparedTransition)
        }

        if preparedTransition == nil {
            preparedTransition = makePreparedTransition(for: preparation)
        }

        cancelScheduledScrollUpdate()
        cancelPendingFocusPublication(resetLastPublicationTime: false)
        isApplyingPosition = true
        let snapshotChanged = applyBrowseSnapshotIfNeeded(
            preparation.snapshot,
            sampledAround: preparation.focusedTokenIndex
        )
        publicationState = PlayerCollectionScrollPublicationState(
            initialIndex: preparation.focusedTokenIndex
        )
        hasFinishedInitialPositioning = false
        lastEmittedFocusedTokenIndex = nil
        imagePipeline.resetThumbnailWindow()
        if snapshotChanged
            || !isTokenFullyVisible(preparation.focusedTokenIndex) {
            centerContent(on: preparation.focusedTokenIndex)
        }
        retainFocusedTokenIndex(preparation.focusedTokenIndex)
        focusedTokenIndex = preparation.focusedTokenIndex
        collectionView.layoutIfNeeded()
        isApplyingPosition = false
        guard let selection = transitionSelection(
            tokenIndex: preparation.focusedTokenIndex
        ) else {
            cancelPreparedTransition()
            return nil
        }
        return selection
    }

    func cancelPreparedTransition() {
        guard let preparedTransition else { return }
        restorePreparedTransition(preparedTransition)
    }

    private func isValid(_ preparation: PlayerCollectionBrowsePreparation) -> Bool {
        preparation.snapshot.pagePosition(
            forTokenIndex: preparation.focusedTokenIndex
        ) != nil
    }

    private func makePreparedTransition(
        for preparation: PlayerCollectionBrowsePreparation
    ) -> PreparedTransition {
        PreparedTransition(
            preparation: preparation,
            contentOffset: collectionView.contentOffset,
            layoutSize: collectionView.bounds.size,
            layoutDisplayScale: lastLayoutDisplayScale > 0
                ? lastLayoutDisplayScale
                : currentLayoutDisplayScale,
            layoutWindowSafeAreaInsets: layoutWindowSafeAreaInsets,
            verticalContentOffsetRange: verticalContentOffsetRange,
            browseSnapshot: browseSnapshot,
            scrollCoordinatorSnapshot: scrollCoordinator.snapshot(),
            imagePipelineSnapshot: imagePipeline.snapshot(),
            layoutAspectState: layoutAspectState
        )
    }

    private func restorePreparedTransition(_ preparedTransition: PreparedTransition) {
        self.preparedTransition = nil
        gridModeCoordinator.resetGeometryState()
        cancelScheduledScrollUpdate()
        cancelPendingFocusPublication(resetLastPublicationTime: false)
        isApplyingPosition = true

        browseSnapshot = preparedTransition.browseSnapshot
        layoutAspectState = preparedTransition.layoutAspectState
        imagePipeline.cancelVisibleCellImageLoads()
        collectionView.reloadData()
        configureCollectionLayout()
        collectionView.layoutIfNeeded()

        let layoutSizeAndScaleUnchanged =
            preparedTransition.layoutSize == collectionView.bounds.size
            && preparedTransition.layoutDisplayScale
                == currentLayoutDisplayScale
        let canRestoreExactGeometry =
            layoutSizeAndScaleUnchanged
            && preparedTransition.layoutWindowSafeAreaInsets
                == layoutWindowSafeAreaInsets
            && preparedTransition.verticalContentOffsetRange
                == verticalContentOffsetRange
        if layoutSizeAndScaleUnchanged {
            let restoredContentOffset = canRestoreExactGeometry
                ? preparedTransition.contentOffset
                : contentOffsetAfterSafeAreaChange(
                    previousContentOffset: preparedTransition.contentOffset,
                    previousTopContentInset:
                        preparedTransition.layoutWindowSafeAreaInsets.top,
                    previousVerticalContentOffsetRange:
                        preparedTransition.verticalContentOffsetRange
                )
            collectionView.setContentOffset(
                restoredContentOffset,
                animated: false
            )
        } else if let focusedTokenIndex = preparedTransition
            .scrollCoordinatorSnapshot.forcedFocusedTokenIndex
            ?? preparedTransition.scrollCoordinatorSnapshot.focusedTokenIndex {
            centerContent(on: focusedTokenIndex)
        } else {
            collectionView.setContentOffset(clampedContentOffset(preparedTransition.contentOffset), animated: false)
        }
        collectionView.layoutIfNeeded()

        let scrollSnapshot = preparedTransition.scrollCoordinatorSnapshot
        let restoredRetainedFocusFocalBias: PlayerCollectionScrollFocalBias?
        if let forcedFocusedTokenIndex = scrollSnapshot.forcedFocusedTokenIndex {
            if canRestoreExactGeometry {
                restoredRetainedFocusFocalBias =
                    scrollSnapshot.retainedFocusFocalBias
                    ?? makeFocalBias(for: forcedFocusedTokenIndex)
            } else {
                restoredRetainedFocusFocalBias =
                    makeFocalBias(for: forcedFocusedTokenIndex)
            }
        } else {
            restoredRetainedFocusFocalBias = canRestoreExactGeometry
                ? scrollSnapshot.retainedFocusFocalBias
                : nil
        }
        scrollCoordinator.restore(
            scrollSnapshot,
            retainedFocusFocalBias: restoredRetainedFocusFocalBias,
            lastScrollOffsetY: canRestoreExactGeometry
                ? scrollSnapshot.lastScrollOffsetY
                : collectionView.contentOffset.y
        )
        imagePipeline.restore(preparedTransition.imagePipelineSnapshot)
        isApplyingPosition = false
        gridModeCoordinator.scheduleGeometryPrewarmIfPossible()
    }

    func scrollToFirstItemAndPublish() {
        guard let pagePosition = browseSnapshot?.pagePosition(forTokenIndex: 0),
              let preparation = playbackSession.prepareCollectionBrowse(
                containing: pagePosition
              ) else {
            return
        }

        endScrollMotionAndResetDragState()
        prepareForDisplay(
            using: preparation,
            forcePosition: true,
            publishWhenStable: true
        ) { _ in }
    }

    func flushSettledPosition() {
        guard isActive else { return }
        gridModeCoordinator.interruptInteractionIfNeeded()
        cancelScheduledScrollUpdate()
        observeCurrentAnchor(
            focusCadence: .immediate,
            preparesThumbnailWindow: false,
            forcesThumbnailWindow: false
        )
        scrollCoordinator.finalFlush(hasViewedToEnd: hasViewedToEnd)
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        browseSnapshot?.itemCount ?? 0
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: Self.cellReuseIdentifier,
            for: indexPath
        )
        guard let browserCell = cell as? MobilePlayerCollectionBrowserCell else { return cell }
        configureBrowserCell(browserCell, at: indexPath)
        gridModeCoordinator.didConfigureCell(browserCell, at: indexPath)
        return browserCell
    }

    func collectionView(
        _ collectionView: UICollectionView,
        willDisplay cell: UICollectionViewCell,
        forItemAt indexPath: IndexPath
    ) {
        gridModeCoordinator.willDisplayCell(cell, at: indexPath)
        guard let browserCell = cell as? MobilePlayerCollectionBrowserCell else {
            return
        }
        imagePipeline.willDisplay(
            cell: browserCell,
            tokenIndex: indexPath.item,
            intersectsViewport: {
                MobilePlayerCollectionBrowserTransitionSupport
                    .itemIntersectsViewport(
                    at: indexPath,
                    cell: browserCell,
                    collectionView: collectionView,
                    viewportView: view
                )
            }
        )
    }

    func collectionView(
        _ collectionView: UICollectionView,
        didEndDisplaying cell: UICollectionViewCell,
        forItemAt indexPath: IndexPath
    ) {
        imagePipeline.willEndDisplaying(tokenIndex: indexPath.item)
        gridModeCoordinator.didEndDisplayingCell(cell, at: indexPath)
        guard let browserCell = cell as? MobilePlayerCollectionBrowserCell else {
            return
        }
        imagePipeline.didEndDisplaying(
            cell: browserCell,
            tokenIndex: indexPath.item
        )
    }

    func collectionView(
        _ collectionView: UICollectionView,
        shouldSelectItemAt indexPath: IndexPath
    ) -> Bool {
        isActive
            && !gridModeCoordinator.hasInteractionState
            && canSelectBrowserCell(at: indexPath.item)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        performSelection(at: indexPath.item)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfigurationForItemAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard isActive,
              !gridModeCoordinator.hasInteractionState,
              canSelectBrowserCell(at: indexPath.item),
              let snapshot = browseSnapshot,
              let descriptor = MobileCollectionBrowseMediaResolver.collectionBrowseThumbnailDescriptor(
                snapshot: snapshot,
                tokenIndex: indexPath.item
              ),
              !descriptor.collectionId.isEmpty,
              !descriptor.tokenId.isEmpty else {
            return nil
        }

        let configuration = UIContextMenuConfiguration(
            identifier: indexPath as NSIndexPath,
            previewProvider: nil
        ) { [weak self] _ in
            guard self?.canSelectBrowserCell(at: indexPath.item) == true else {
                return nil
            }
            let token = MobileCollectionCatalog.generateToken(
                specificCollectionId: descriptor.collectionId,
                tokenIndex: descriptor.tokenIndex
            )

            var children: [UIMenuElement] = [
                UIDeferredMenuElement.uncached { completion in
                    Task {
                        let storedState = PlayerBookmarksStore.storedBookmarkState(
                            collectionId: descriptor.collectionId,
                            tokenId: descriptor.tokenId
                        )
                        let resolvedIsBookmarked = storedState.isReady
                            ? storedState.isBookmarked
                            : await PlayerBookmarksStore.shared.isBookmarked(
                                collectionId: descriptor.collectionId,
                                tokenId: descriptor.tokenId
                            )
                        let latestState = PlayerBookmarksStore.storedBookmarkState(
                            collectionId: descriptor.collectionId,
                            tokenId: descriptor.tokenId
                        )
                        let isBookmarked = latestState.isReady
                            ? latestState.isBookmarked
                            : resolvedIsBookmarked
                        let action = UIAction(
                            title: isBookmarked ? Strings.removeBookmark : Strings.bookmark,
                            image: UIImage(
                                systemName: isBookmarked ? "bookmark.fill" : "bookmark"
                            ),
                            attributes: latestState.isTogglePending ? .disabled : []
                        ) { _ in
                            let didBeginToggle = PlayerBookmarksStore.enqueueBookmarkUpdate(
                                collectionId: descriptor.collectionId,
                                tokenId: descriptor.tokenId,
                                isBookmarked: !isBookmarked
                            )
                            if didBeginToggle {
                                Haptic.selectionChanged()
                            }
                        }
                        completion([action])
                    }
                }
            ]
            if let url = token?.url {
                children.append(
                    UIAction(title: Strings.viewOnBlockExplorer, image: UIImage(systemName: "globe")) { _ in
                        UIApplication.shared.open(url)
                    }
                )
            }

            return UIMenu(title: token?.displayName ?? "", children: children)
        }
        configuration.preferredMenuElementOrder = .fixed
        return configuration
    }

    func collectionView(
        _ collectionView: UICollectionView,
        willPerformPreviewActionForMenuWith configuration: UIContextMenuConfiguration,
        animator: UIContextMenuInteractionCommitAnimating
    ) {
        guard let indexPath = configuration.identifier as? IndexPath else { return }
        let tokenIndex = indexPath.item
        guard canSelectBrowserCell(at: tokenIndex) else {
            animator.preferredCommitStyle = .dismiss
            return
        }
        guard let pagePosition = browseSnapshot?.pagePosition(forTokenIndex: tokenIndex) else {
            animator.preferredCommitStyle = .dismiss
            animator.addCompletion { [weak self] in
                self?.performSelection(at: tokenIndex)
            }
            return
        }

        var didFinishCommitAnimation = false
        var didFailSwitch = false
        var didRunFallback = false
        let runFallbackIfReady = { [weak self] in
            guard didFinishCommitAnimation,
                  didFailSwitch,
                  !didRunFallback else {
                return
            }
            didRunFallback = true
            self?.performSelection(at: tokenIndex)
        }
        guard onImmediateSelection?(pagePosition, {
            didFailSwitch = true
            runFallbackIfReady()
        }) == true else {
            animator.preferredCommitStyle = .dismiss
            animator.addCompletion { [weak self] in
                self?.performSelection(at: tokenIndex)
            }
            return
        }

        animator.preferredCommitStyle = .pop
        animator.addCompletion {
            didFinishCommitAnimation = true
            runFallbackIfReady()
        }
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        gridModeCoordinator.prepareForDragging()
        cancelScrollMotionAnimationTimeout()
        if scrollCoordinator.beginDrag(
            contentOffsetY: scrollView.contentOffset.y,
            clampedContentOffsetY:
                clampedVerticalContentOffsetY(scrollView.contentOffset.y)
        ) {
            beginScrollSessionSignpost()
            imagePipeline.setScrollMotionActive(true)
            gridModeCoordinator.dragDidBeginScrollMotion()
            demoteVisibleBrowserImageLoadsIfNeeded()
            prepareCurrentImageWindowIfPossible()
        }
        let verticalRange = verticalContentOffsetRange
        if verticalRange.upperBound - verticalRange.lowerBound <= Self.boundaryEpsilon,
           scrollCoordinator.markCurrentDragAcknowledged() {
            playbackSession.acknowledgeIntentionalViewingPosition()
        }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let gridModeObservation = gridModeCoordinator
            .observeScrollDuringGridMode(scrollView)
        guard gridModeObservation.shouldContinue else { return }
        let previousOffsetY = scrollCoordinator.observeContentOffset(
            scrollView.contentOffset.y
        )
        guard isActive,
              hasFinishedInitialPositioning,
              !isApplyingPosition else {
            return
        }
        releaseRetainedFocusForOutwardPullIfNeeded(scrollView)
        acknowledgeIntentionalScrollIfNeeded(scrollView)
        if let previousOffsetY {
            let offsetDelta = PlayerCollectionScrollPolicy.boundedContentOffsetDelta(
                previousOffsetY: previousOffsetY,
                currentOffsetY: scrollView.contentOffset.y,
                validRange: verticalContentOffsetRange
            )
            _ = scrollCoordinator.updatePrefetchDirection(
                offsetDelta: offsetDelta,
                epsilon: Self.boundaryEpsilon
            )
        }
        scheduleScrollUpdate()
        if gridModeObservation.settlesAfterImmediateOffset {
            gridModeCoordinator.settleAfterImmediateOffsetIfPossible()
        }
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        guard !decelerate else { return }
        endScrollMotionAndResetDragState()
        settleAfterApplyingPendingWindowSafeAreaRefresh()
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        endScrollMotionAndResetDragState()
        settleAfterApplyingPendingWindowSafeAreaRefresh()
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        settleScrollMotionIfIdle(scrollView)
    }

    private func settleScrollMotionIfIdle(_ scrollView: UIScrollView) {
        guard !scrollView.isTracking,
              !scrollView.isDragging,
              !scrollView.isDecelerating,
              dragStartContentOffsetY == nil else {
            return
        }
        endScrollMotion()
        settleAfterApplyingPendingWindowSafeAreaRefresh()
    }

    func scrollViewShouldScrollToTop(_ scrollView: UIScrollView) -> Bool {
        guard isActive else { return false }
        let interruptedGridModeSettle = gridModeCoordinator
            .finalizeInterruptibleSettle()
        guard !gridModeCoordinator.hasInteractionState else { return false }
        endScrollMotionAndResetDragState()
        let hasScrollMotion =
            scrollView.contentOffset.y
                > verticalContentOffsetRange.lowerBound + Self.boundaryEpsilon
        if hasScrollMotion {
            beginScrollMotion()
            gridModeCoordinator.discardTransitionCover()
            scheduleScrollMotionAnimationTimeout()
        }
        retainFocusedTokenIndex(nil)
        cancelScheduledScrollUpdate()
        lastScrollOffsetY = scrollView.contentOffset.y
        if interruptedGridModeSettle, !hasScrollMotion {
            gridModeCoordinator.settleAfterImmediateOffsetIfPossible()
        }
        return true
    }

    func scrollViewDidScrollToTop(_ scrollView: UIScrollView) {
        settleScrollMotionIfIdle(scrollView)
    }

    private func applyBrowseSnapshotIfNeeded(
        _ snapshot: PlayerCollectionBrowseSnapshot?,
        sampledAround focusedTokenIndex: Int?
    ) -> Bool {
        let snapshotChanged = browseSnapshot != snapshot
        if snapshotChanged {
            applyBrowseSnapshot(
                snapshot,
                sampledAround: focusedTokenIndex,
                gridMode: gridMode
            )
        }
        return snapshotChanged
    }

    private func applyBrowseSnapshot(
        _ snapshot: PlayerCollectionBrowseSnapshot?,
        sampledAround focusedTokenIndex: Int?,
        gridMode: MobileCollectionBrowserGridMode
    ) {
        gridModeCoordinator.applyBrowseSnapshot(
            snapshot,
            sampledAround: focusedTokenIndex,
            gridMode: gridMode
        )
    }

    private func updateLayoutAspectProfile(
        snapshot: PlayerCollectionBrowseSnapshot?,
        focusedTokenIndex: Int?,
        columnCount: Int
    ) {
        let defaultSize = CGSize(width: 1, height: 1)
        guard let snapshot,
              snapshot.itemCount > 0 else {
            layoutAspectState = MobilePlayerCollectionBrowserLayoutAspectState(
                aspectProfile: MobilePlayerBrowserAspectProfile(
                    itemCount: 0,
                    uniformImageSize: defaultSize,
                    columnCount: columnCount
                ),
                fallbackSpec: PlayerMediaPlaceholderSpec(
                    aspectSize: defaultSize
                )
            )
            return
        }

        let aspectRatioProfile = MobileCollectionBrowseMediaResolver
            .collectionBrowseThumbnailAspectRatioProfile(snapshot: snapshot)
        let aspectState = makeLayoutAspectState(
            snapshot: snapshot,
            columnCount: columnCount,
            focusedTokenIndex: focusedTokenIndex,
            aspectRatioProfile: aspectRatioProfile
        )
        layoutAspectState = aspectState
    }

    private func makeLayoutAspectState(
        snapshot: PlayerCollectionBrowseSnapshot,
        columnCount: Int,
        focusedTokenIndex: Int?,
        aspectRatioProfile: ThumbnailAspectRatioProfile?
    ) -> MobilePlayerCollectionBrowserLayoutAspectState {
        let defaultSize = CGSize(width: 1, height: 1)
        let sampleState = makeLayoutAspectSamples(
            snapshot: snapshot,
            focusedTokenIndex: focusedTokenIndex
        )

        let aspectProfile: MobilePlayerBrowserAspectProfile
        if let aspectRatioProfile {
            aspectProfile = makeLayoutAspectProfile(
                snapshot: snapshot,
                columnCount: columnCount,
                aspectRatioProfile: aspectRatioProfile
            )
        } else {
            let layoutFallbackSize = sampleState.samples
                .map(\.size)
                .max {
                    $0.height / $0.width < $1.height / $1.width
                }
                ?? defaultSize
            aspectProfile = MobilePlayerBrowserAspectProfile(
                itemCount: snapshot.itemCount,
                uniformImageSize: layoutFallbackSize,
                columnCount: columnCount
            )
        }

        return MobilePlayerCollectionBrowserLayoutAspectState(
            aspectProfile: aspectProfile,
            fallbackSpec: makeLayoutFallbackSpec(
                focus: sampleState.focus,
                samples: sampleState.samples
            )
        )
    }

    private func makeLayoutAspectSamples(
        snapshot: PlayerCollectionBrowseSnapshot,
        focusedTokenIndex: Int?
    ) -> (focus: Int, samples: [LayoutAspectSample]) {
        guard snapshot.itemCount > 0 else { return (0, []) }
        let sampleCount = min(
            snapshot.itemCount,
            MobilePlayerBrowserLayout.maximumAspectSampleCount
        )
        let focus = min(max(focusedTokenIndex ?? snapshot.initialTokenIndex, 0), snapshot.itemCount - 1)
        let firstIndex = min(
            max(focus - sampleCount / 2, 0),
            snapshot.itemCount - sampleCount
        )
        let sampleRange = firstIndex..<(firstIndex + sampleCount)
        let samples = sampleRange.compactMap { tokenIndex -> LayoutAspectSample? in
            guard let descriptor = MobileCollectionBrowseMediaResolver.collectionBrowseThumbnailDescriptor(
                snapshot: snapshot,
                tokenIndex: tokenIndex
            ) else {
                return nil
            }
            let size = PlayerCollectionBrowserSupport.fallbackImageSize(for: descriptor)
            guard size.width.isFinite,
                  size.height.isFinite,
                  size.width > 0,
                  size.height > 0 else {
                return nil
            }
            return LayoutAspectSample(
                index: tokenIndex,
                size: size,
                usesNativeMetalCardCornerMask:
                    descriptor.usesNativeMetalCardPresentation
            )
        }
        return (focus, samples)
    }

    private func makeLayoutFallbackSpec(
        snapshot: PlayerCollectionBrowseSnapshot,
        focusedTokenIndex: Int?
    ) -> PlayerMediaPlaceholderSpec {
        let sampleState = makeLayoutAspectSamples(
            snapshot: snapshot,
            focusedTokenIndex: focusedTokenIndex
        )
        return makeLayoutFallbackSpec(
            focus: sampleState.focus,
            samples: sampleState.samples
        )
    }

    private func makeLayoutFallbackSpec(
        focus: Int,
        samples: [LayoutAspectSample]
    ) -> PlayerMediaPlaceholderSpec {
        let nearestSample = samples.min { lhs, rhs in
            let lhsDistance = abs(lhs.index - focus)
            let rhsDistance = abs(rhs.index - focus)
            return lhsDistance == rhsDistance
                ? lhs.index < rhs.index
                : lhsDistance < rhsDistance
        }
        return PlayerMediaPlaceholderSpec(
            aspectSize: nearestSample?.size ?? CGSize(width: 1, height: 1),
            usesNativeMetalCardCornerMask:
                nearestSample?.usesNativeMetalCardCornerMask ?? false
        )
    }

    private func makeLayoutAspectProfile(
        snapshot: PlayerCollectionBrowseSnapshot,
        columnCount: Int,
        aspectRatioProfile: ThumbnailAspectRatioProfile
    ) -> MobilePlayerBrowserAspectProfile {
        switch aspectRatioProfile {
        case let .uniform(aspectRatio):
            return MobilePlayerBrowserAspectProfile(
                itemCount: snapshot.itemCount,
                uniformImageSize: aspectRatio.size,
                columnCount: columnCount
            )
        case let .variable(aspectRatios):
            return MobilePlayerBrowserAspectProfile(
                heightToWidthRatios: aspectRatios.map {
                    CGFloat($0.height) / CGFloat($0.width)
                },
                columnCount: columnCount
            )
        }
    }

    private func reloadBrowseSnapshot(resetPublicationState: Bool) {
        let newSnapshot = playbackSession.collectionBrowseSnapshot()
        let snapshotChanged = newSnapshot != browseSnapshot
        guard snapshotChanged || resetPublicationState else { return }

        if !resetPublicationState,
           snapshotChanged,
           let newSnapshot,
           let currentSnapshot = browseSnapshot,
           CollectionBrowseSnapshotUpdatePolicy.isSettledPositionEcho(
               currentCollectionId: currentSnapshot.collectionId,
               currentItemCount: currentSnapshot.itemCount,
               updatedCollectionId: newSnapshot.collectionId,
               updatedItemCount: newSnapshot.itemCount,
               updatedInitialTokenIndex: newSnapshot.initialTokenIndex,
               lastPublishedTokenIndex:
                   publicationState?.lastPublishedTokenIndex
           ) {
            browseSnapshot = newSnapshot
            return
        }

        let restorationIndex = PlayerCollectionScrollPolicy.restorationIndex(
            savedIndex: newSnapshot?.initialTokenIndex,
            itemCount: newSnapshot?.itemCount ?? 0
        )
        applyBrowseSnapshot(
            newSnapshot,
            sampledAround: restorationIndex,
            gridMode: gridMode
        )

        publicationState = restorationIndex.map {
            PlayerCollectionScrollPublicationState(initialIndex: $0)
        }
        hasFinishedInitialPositioning = false
        focusedTokenIndex = restorationIndex
        retainFocusedTokenIndex(restorationIndex)
        lastEmittedFocusedTokenIndex = nil
        imagePipeline.resetThumbnailWindow()
        cancelPendingFocusPublication(resetLastPublicationTime: true)
    }

    private func performInitialPositioningIfNeeded() {
        guard !hasFinishedInitialPositioning,
              lastLayoutSize != .zero,
              let browseSnapshot,
              let targetTokenIndex = PlayerCollectionScrollPolicy.restorationIndex(
                savedIndex: browseSnapshot.initialTokenIndex,
                itemCount: browseSnapshot.itemCount
              ),
              collectionView.bounds.width > 0,
              collectionView.bounds.height > 0 else {
            return
        }

        isApplyingPosition = true
        centerContent(on: targetTokenIndex)
        retainFocusedTokenIndex(targetTokenIndex)
        focusedTokenIndex = targetTokenIndex
        collectionView.layoutIfNeeded()
        isApplyingPosition = false
        hasFinishedInitialPositioning = true
        publicationState?.finishInitialPositioning()
        publicationState?.observeCandidate(targetTokenIndex)
        publishFocus(tokenIndex: targetTokenIndex, cadence: .immediate)
        publishSettledTokenIfNeeded()
        prepareThumbnailWindow(around: targetTokenIndex, direction: .forward, force: true)
        gridModeCoordinator.scheduleGeometryPrewarmIfPossible()
    }

    private func configureCollectionLayout() {
        guard let browserLayout = makeBrowserLayout(
            aspectProfile: layoutAspectState.aspectProfile
        ) else {
            return
        }

        installCollectionLayout(browserLayout)
    }

    private func makeBrowserLayout(
        aspectProfile: MobilePlayerBrowserAspectProfile
    ) -> MobilePlayerBrowserLayout? {
        let viewportSize = view.bounds.size
        guard viewportSize.width > 0, viewportSize.height > 0 else { return nil }

        return MobilePlayerBrowserLayout(
            viewportSize: viewportSize,
            displayScale: currentLayoutDisplayScale,
            topContentInset:
                Self.verticalContentMargin + layoutWindowSafeAreaInsets.top,
            bottomContentInset:
                Self.verticalContentMargin + layoutWindowSafeAreaInsets.bottom,
            aspectProfile: aspectProfile
        )
    }

    private func installCollectionLayout(
        _ browserLayout: MobilePlayerBrowserLayout
    ) {
        let thumbnailWindowCadenceChanged =
            configuredPrefetchStride != browserLayout.prefetchStride
                || configuredColumnCount != browserLayout.columnCount
        browserCollectionLayout.browserLayout = browserLayout
        if thumbnailWindowCadenceChanged {
            imagePipeline.resetThumbnailWindow()
        }
        collectionView.scrollIndicatorInsets = UIEdgeInsets(
            top: layoutWindowSafeAreaInsets.top,
            left: 0,
            bottom: layoutWindowSafeAreaInsets.bottom,
            right: 0
        )
        gridModeCoordinator.scheduleGeometryPrewarmIfPossible()
    }

    private func captureLayoutWindowSafeAreaInsets(_ safeAreaInsets: UIEdgeInsets) {
        layoutWindowSafeAreaInsets = UIEdgeInsets(
            top: safeAreaInsets.top.isFinite ? max(safeAreaInsets.top, 0) : 0,
            left: 0,
            bottom: safeAreaInsets.bottom.isFinite ? max(safeAreaInsets.bottom, 0) : 0,
            right: 0
        )
        hasCapturedLayoutWindowSafeAreaInsets = true
    }

    private func resolveWindowSafeAreaLayoutUpdate(
        state: WindowSafeAreaState?,
        sizeChanged: Bool
    ) -> WindowSafeAreaLayoutUpdate {
        guard let state else {
            return WindowSafeAreaLayoutUpdate(
                insetsToCapture: nil,
                clearsPendingRefresh: false,
                requiresLayoutRefresh: false
            )
        }

        let needsInitialCapture = !hasCapturedLayoutWindowSafeAreaInsets
        let isScrollInteractionActive = isScrollMotionActive
        let canEvaluatePendingRefresh =
            needsWindowSafeAreaRefresh
            && !isScrollInteractionActive
        let shouldCaptureInsets =
            sizeChanged || needsInitialCapture || canEvaluatePendingRefresh
        let resolvedInsets = shouldCaptureInsets
            ? UIEdgeInsets(
                top: sizeChanged || needsInitialCapture
                    ? state.insets.top
                    : layoutWindowSafeAreaInsets.top,
                left: 0,
                bottom: state.insets.bottom,
                right: 0
            )
            : nil
        let insetsChanged =
            resolvedInsets.map { $0 != layoutWindowSafeAreaInsets } == true

        return WindowSafeAreaLayoutUpdate(
            insetsToCapture: resolvedInsets,
            clearsPendingRefresh: shouldCaptureInsets,
            requiresLayoutRefresh:
                needsInitialCapture
                    || (!sizeChanged && insetsChanged)
        )
    }

    private var currentWindowSafeAreaState: WindowSafeAreaState? {
        guard let window = collectionView.window else { return nil }

        let safeAreaInsets = collectionView.safeAreaInsets

        let displayScale = window.screen.scale
        func pixelAligned(_ value: CGFloat) -> CGFloat {
            let sanitizedValue = value.isFinite ? max(value, 0) : 0
            guard displayScale.isFinite, displayScale > 0 else {
                return sanitizedValue
            }
            return (sanitizedValue * displayScale).rounded() / displayScale
        }

        return WindowSafeAreaState(
            insets: UIEdgeInsets(
                top: pixelAligned(safeAreaInsets.top),
                left: 0,
                bottom: pixelAligned(safeAreaInsets.bottom),
                right: 0
            )
        )
    }

    private var currentLayoutDisplayScale: CGFloat {
        let traitScale = traitCollection.displayScale
        if traitScale.isFinite, traitScale > 0 {
            return traitScale
        }
        let windowScale = view.window?.screen.scale ?? 0
        return windowScale.isFinite && windowScale > 0 ? windowScale : 3
    }

    private func restoreContentPositionAfterSafeAreaChange(
        previousContentOffset: CGPoint,
        previousTopContentInset: CGFloat,
        previousVerticalContentOffsetRange: ClosedRange<CGFloat>,
        retainedFocusTokenIndex: Int?
    ) {
        let restoredContentOffset = contentOffsetAfterSafeAreaChange(
            previousContentOffset: previousContentOffset,
            previousTopContentInset: previousTopContentInset,
            previousVerticalContentOffsetRange:
                previousVerticalContentOffsetRange
        )
        let appliedOffsetDeltaY =
            restoredContentOffset.y - previousContentOffset.y
        collectionView.setContentOffset(restoredContentOffset, animated: false)
        scrollCoordinator.adjustDragStartContentOffset(
            by: appliedOffsetDeltaY
        )

        retainFocusedTokenIndex(retainedFocusTokenIndex)
        if let retainedFocusTokenIndex {
            focusedTokenIndex = retainedFocusTokenIndex
        }
    }

    private func contentOffsetAfterSafeAreaChange(
        previousContentOffset: CGPoint,
        previousTopContentInset: CGFloat,
        previousVerticalContentOffsetRange: ClosedRange<CGFloat>
    ) -> CGPoint {
        let restoredContentOffsetY =
            MobilePlayerBrowserLayout.contentOffsetYAfterSafeAreaChange(
                previousContentOffsetY: previousContentOffset.y,
                previousRange: previousVerticalContentOffsetRange,
                updatedRange: verticalContentOffsetRange,
                topContentInsetDelta:
                    layoutWindowSafeAreaInsets.top
                        - previousTopContentInset,
                boundaryEpsilon: Self.boundaryEpsilon
            )
        return clampedContentOffset(
            CGPoint(
                x: previousContentOffset.x,
                y: restoredContentOffsetY
            )
        )
    }

    private func centerContent(on tokenIndex: Int) {
        guard let browseSnapshot,
              (0..<browseSnapshot.itemCount).contains(tokenIndex) else {
            return
        }

        collectionView.layoutIfNeeded()
        let indexPath = IndexPath(item: tokenIndex, section: 0)
        guard let attributes = collectionView.collectionViewLayout.layoutAttributesForItem(at: indexPath) else {
            collectionView.scrollToItem(
                at: indexPath,
                at: .centeredVertically,
                animated: false
            )
            return
        }

        let proposedOffsetY: CGFloat
        if let focalGeometry {
            proposedOffsetY = focalGeometry.contentOffsetY(
                anchoringFocalY: attributes.frame.midY
            )
        } else {
            proposedOffsetY = attributes.frame.midY - collectionView.bounds.height / 2
        }
        collectionView.setContentOffset(
            clampedContentOffset(CGPoint(x: 0, y: proposedOffsetY)),
            animated: false
        )
    }

    private var canonicalContentOffsetX: CGFloat {
        -collectionView.adjustedContentInset.left
    }

    private func clampedContentOffset(_ contentOffset: CGPoint) -> CGPoint {
        return CGPoint(
            x: canonicalContentOffsetX,
            y: clampedVerticalContentOffsetY(contentOffset.y)
        )
    }

    private func clampedVerticalContentOffsetY(_ contentOffsetY: CGFloat) -> CGFloat {
        let verticalRange = verticalContentOffsetRange
        return min(max(contentOffsetY, verticalRange.lowerBound), verticalRange.upperBound)
    }

    private var verticalContentOffsetRange: ClosedRange<CGFloat> {
        let minimumOffsetY = -collectionView.adjustedContentInset.top
        let maximumOffsetY = max(
            minimumOffsetY,
            collectionView.contentSize.height
                - collectionView.bounds.height
                + collectionView.adjustedContentInset.bottom
        )
        return minimumOffsetY...maximumOffsetY
    }

    private var hasViewedToEnd: Bool {
        guard let browseSnapshot,
              browseSnapshot.itemCount > 0,
              let attributes = collectionView.collectionViewLayout.layoutAttributesForItem(
                at: IndexPath(item: browseSnapshot.itemCount - 1, section: 0)
              ) else {
            return false
        }
        return PlayerCollectionScrollPolicy.hasViewedToEnd(
            finalItemFrame: attributes.frame,
            viewport: collectionView.bounds,
            maximumContentOffsetY: verticalContentOffsetRange.upperBound,
            epsilon: Self.boundaryEpsilon
        )
    }

    private func isTokenFullyVisible(_ tokenIndex: Int) -> Bool {
        let indexPath = IndexPath(item: tokenIndex, section: 0)
        guard let attributes = collectionView.collectionViewLayout.layoutAttributesForItem(at: indexPath) else {
            return false
        }
        return PlayerCollectionScrollPolicy.isItemFullyVisible(
            frame: attributes.frame,
            viewport: collectionView.bounds,
            epsilon: Self.boundaryEpsilon
        )
    }

    private func releaseRetainedFocusForOutwardPullIfNeeded(_ scrollView: UIScrollView) {
        guard forcedFocusedTokenIndex != nil else { return }
        let verticalRange = verticalContentOffsetRange
        guard verticalRange.upperBound - verticalRange.lowerBound > Self.boundaryEpsilon else {
            return
        }
        let contentOffsetY = scrollView.contentOffset.y
        let isOutwardPull = contentOffsetY < verticalRange.lowerBound - Self.boundaryEpsilon
            || contentOffsetY > verticalRange.upperBound + Self.boundaryEpsilon
        guard isOutwardPull else { return }
        retainFocusedTokenIndex(nil)
    }

    private func acknowledgeIntentionalScrollIfNeeded(_ scrollView: UIScrollView) {
        let currentContentOffsetY = clampedVerticalContentOffsetY(scrollView.contentOffset.y)
        guard scrollCoordinator.acknowledgeIntentionalScrollIfNeeded(
            clampedContentOffsetY: currentContentOffsetY,
            epsilon: Self.boundaryEpsilon
        ) else { return }
        playbackSession.acknowledgeIntentionalViewingPosition()
    }

    private func endScrollMotionAndResetDragState() {
        endScrollMotion()
        scrollCoordinator.resetDragState()
        if needsWindowSafeAreaRefresh {
            view.setNeedsLayout()
        }
    }

    private func beginScrollMotion() {
        guard scrollCoordinator.beginScrollMotion() else { return }
        beginScrollSessionSignpost()
        imagePipeline.setScrollMotionActive(true)
        gridModeCoordinator.cancelGeometryPrewarming()
        demoteVisibleBrowserImageLoadsIfNeeded()
        prepareCurrentImageWindowIfPossible()
    }

    private func endScrollMotion() {
        scrollCoordinator.endScrollMotion()
        endScrollSessionSignpost()
        imagePipeline.setScrollMotionActive(false)
        imagePipeline.cancelDenseGridImageRefreshes()
        if needsWindowSafeAreaRefresh {
            view.setNeedsLayout()
        }
    }

    private func beginScrollSessionSignpost() {
        guard scrollSessionSignpost == nil else { return }
        scrollSessionSignpost = Self.signposter.beginInterval("ScrollSession")
    }

    private func endScrollSessionSignpost() {
        if let scrollSessionSignpost {
            Self.signposter.endInterval("ScrollSession", scrollSessionSignpost)
            self.scrollSessionSignpost = nil
        }
    }

    private func cancelScrollMotionAnimationTimeout() {
        scrollCoordinator.cancelScrollMotionAnimationTimeout()
    }

    private func scheduleScrollMotionAnimationTimeout() {
        scrollCoordinator.scheduleScrollMotionAnimationTimeout()
    }

    private func handleScrollMotionAnimationTimeout() {
        endScrollMotion()
        settleAfterApplyingPendingWindowSafeAreaRefresh()
    }

    private func settleAfterApplyingPendingWindowSafeAreaRefresh() {
        guard !isApplyingPosition else { return }
        if needsWindowSafeAreaRefresh,
           let currentAnchorTokenIndex = currentAnchorTokenIndex() {
            focusedTokenIndex = currentAnchorTokenIndex
        }
        let previousSettlementGeneration = scrollCoordinator.settlementGeneration
        if needsWindowSafeAreaRefresh {
            view.setNeedsLayout()
        }
        view.layoutIfNeeded()
        if scrollCoordinator.settlementGeneration == previousSettlementGeneration {
            settleCurrentPosition()
        }
    }

    private func currentAnchorTokenIndex() -> Int? {
        guard let browseSnapshot,
              let browserLayout = browserCollectionLayout.browserLayout else {
            return nil
        }

        let visibleItems = collectionView.indexPathsForVisibleItems.compactMap {
            indexPath -> PlayerCollectionVisibleItem? in
            guard let frame = browserLayout.itemFrame(at: indexPath.item) else {
                return nil
            }
            return PlayerCollectionVisibleItem(
                index: indexPath.item,
                frame: frame
            )
        }
        let candidateIndex = PlayerCollectionScrollPolicy.anchorIndex(
            visibleItems: visibleItems,
            focalPoint: currentFocalPoint(),
            itemCount: browseSnapshot.itemCount
        )
        let resolvedIndex = PlayerCollectionScrollPolicy.resolvedAnchorIndex(
            retainedIndex: forcedFocusedTokenIndex,
            candidateIndex: candidateIndex,
            itemCount: browseSnapshot.itemCount,
            configuredColumnCount: configuredColumnCount
        )
        if forcedFocusedTokenIndex != nil,
           resolvedIndex != forcedFocusedTokenIndex {
            forcedFocusedTokenIndex = nil
        }
        return resolvedIndex
    }

    private func retainFocusedTokenIndex(_ tokenIndex: Int?) {
        forcedFocusedTokenIndex = tokenIndex
        retainedFocusFocalBias = tokenIndex.flatMap { makeFocalBias(for: $0) }
    }

    private func currentFocalPoint() -> CGPoint {
        let viewport = collectionView.bounds
        guard let focalGeometry else {
            return CGPoint(x: viewport.midX, y: viewport.midY)
        }

        let standardFocalPoint = focalGeometry.focalPoint(at: collectionView.contentOffset.y)
        guard let retainedFocusFocalBias else {
            return standardFocalPoint
        }

        let adjustedFocalPoint = retainedFocusFocalBias.adjustedFocalPoint(
            from: standardFocalPoint,
            minimumFocalY: focalGeometry.firstItemCenter.y,
            maximumFocalY: focalGeometry.lastItemCenter.y
        )
        if retainedFocusFocalBias.isExpired(
            at: standardFocalPoint.y,
            minimumFocalY: focalGeometry.firstItemCenter.y,
            maximumFocalY: focalGeometry.lastItemCenter.y
        ) {
            self.retainedFocusFocalBias = nil
        }
        return adjustedFocalPoint
    }

    private var focalGeometry: PlayerCollectionScrollFocalGeometry? {
        guard let browseSnapshot,
              browseSnapshot.itemCount > 0,
              configuredColumnCount > 0,
              collectionView.bounds.width > 0,
              collectionView.bounds.height > 0,
              let browserLayout = browserCollectionLayout.browserLayout,
              let firstItemFrame = browserLayout.itemFrame(at: 0),
              let lastItemFrame = browserLayout.itemFrame(
                at: browseSnapshot.itemCount - 1
              ) else {
            return nil
        }

        let lastRowFirstIndex = ((browseSnapshot.itemCount - 1) / configuredColumnCount)
            * configuredColumnCount
        let lastRowFocalEntryY: CGFloat
        if lastRowFirstIndex > 0,
           let previousRowFrame = browserLayout.itemFrame(
                at: lastRowFirstIndex - configuredColumnCount
           ) {
            lastRowFocalEntryY = (
                previousRowFrame.midY + lastItemFrame.midY
            ) / 2
        } else {
            lastRowFocalEntryY = firstItemFrame.midY
        }

        let verticalRange = verticalContentOffsetRange
        return PlayerCollectionScrollFocalGeometry(
            minimumOffsetY: verticalRange.lowerBound,
            maximumOffsetY: verticalRange.upperBound,
            viewportHeight: collectionView.bounds.height,
            viewportCenterX: collectionView.bounds.midX,
            firstItemCenter: CGPoint(
                x: firstItemFrame.midX,
                y: firstItemFrame.midY
            ),
            lastItemCenter: CGPoint(
                x: lastItemFrame.midX,
                y: lastItemFrame.midY
            ),
            lastRowFocalEntryY: lastRowFocalEntryY
        )
    }

    private func makeFocalBias(for tokenIndex: Int) -> PlayerCollectionScrollFocalBias? {
        guard let focalGeometry,
              let attributes = collectionView.collectionViewLayout.layoutAttributesForItem(
                at: IndexPath(item: tokenIndex, section: 0)
              ) else {
            return nil
        }

        let contentOffsetY = clampedVerticalContentOffsetY(collectionView.contentOffset.y)
        let standardFocalPoint = focalGeometry.focalPoint(at: contentOffsetY)
        let targetCenterY = attributes.frame.midY
        let rowTravel = max(
            browserCollectionLayout.browserLayout?
                .minimumAdjacentRowCenterDistance(
                    containingItemAt: tokenIndex
                ) ?? attributes.frame.height + (
                    browserCollectionLayout.browserLayout?.interItemSpacing
                        ?? MobilePlayerBrowserLayout.itemSpacing
                ),
            1
        )
        return PlayerCollectionScrollFocalBias(
            referenceFocalY: standardFocalPoint.y,
            deltaY: targetCenterY - standardFocalPoint.y,
            decayDistance: max(
                abs(targetCenterY - standardFocalPoint.y),
                rowTravel
            )
        )
    }

    private func observeCurrentAnchor(
        focusCadence:
            MobilePlayerCollectionBrowserScrollCoordinator
                .FocusPublicationCadence,
        preparesThumbnailWindow: Bool,
        forcesThumbnailWindow: Bool
    ) {
        guard let tokenIndex = currentAnchorTokenIndex() else { return }
        scrollCoordinator.observe(
            tokenIndex: tokenIndex,
            focusCadence: focusCadence
        )
        if preparesThumbnailWindow {
            prepareThumbnailWindow(
                around: tokenIndex,
                direction: lastPrefetchDirection,
                force: forcesThumbnailWindow
            )
        }
    }

    private func settleCurrentPosition() {
        guard isActive else { return }
        scrollCoordinator.beginSettlement()
        resumeVisibleBrowserImageLoadsIfNeeded()
        observeCurrentAnchor(
            focusCadence: .immediate,
            preparesThumbnailWindow: true,
            forcesThumbnailWindow: true
        )
        publishSettledTokenIfNeeded()
        gridModeCoordinator.scheduleGeometryPrewarmIfPossible()
    }

    private func performSelection(at tokenIndex: Int) {
        guard !gridModeCoordinator.hasInteractionState,
              canSelectBrowserCell(at: tokenIndex) else {
            return
        }
        endScrollMotionAndResetDragState()
        guard let selection = transitionSelection(tokenIndex: tokenIndex) else {
            settleCurrentPosition()
            return
        }
        guard onSelection?(selection) == true else {
            settleCurrentPosition()
            return
        }
        settleSelection(at: tokenIndex)
    }

    private func settleSelection(at tokenIndex: Int) {
        guard isActive,
              browseSnapshot?.pagePosition(forTokenIndex: tokenIndex) != nil else {
            return
        }

        scrollCoordinator.cancelScheduledScrollUpdate()
        retainFocusedTokenIndex(tokenIndex)
        playbackSession.acknowledgeIntentionalViewingPosition()
        scrollCoordinator.observe(
            tokenIndex: tokenIndex,
            focusCadence: .immediate
        )
        publishSettledTokenIfNeeded()
    }

    private func scheduleScrollUpdate() {
        scrollCoordinator.scheduleScrollUpdate()
    }

    private func cancelScheduledScrollUpdate() {
        scrollCoordinator.cancelScheduledScrollUpdate()
    }

    private func publishFocus(
        tokenIndex: Int,
        cadence:
            MobilePlayerCollectionBrowserScrollCoordinator
                .FocusPublicationCadence
    ) {
        scrollCoordinator.publishFocus(tokenIndex: tokenIndex, cadence: cadence)
    }

    private func cancelPendingFocusPublication(resetLastPublicationTime: Bool) {
        scrollCoordinator.cancelPendingFocusPublication(
            resetLastPublicationTime: resetLastPublicationTime
        )
    }

    private func publishSettledTokenIfNeeded() {
        scrollCoordinator.settle(hasViewedToEnd: hasViewedToEnd)
    }

    private func publishSettledPagePosition(
        _ publication: PlayerCollectionScrollPublication
    ) -> Bool {
        guard let pagePosition = browseSnapshot?.pagePosition(
            forTokenIndex: publication.tokenIndex
        ) else {
            return false
        }
        return onSettledPagePosition?(
            pagePosition,
            publication.hasViewedToEnd
        ) == true
    }

    private func prepareThumbnailWindow(
        around tokenIndex: Int,
        direction: DownloadableMediaCache.PrefetchDirection,
        force: Bool
    ) {
        imagePipeline.prepareThumbnailWindow(
            around: tokenIndex,
            direction: direction,
            force: force,
            configuredPrefetchStride: configuredPrefetchStride,
            configuredColumnCount: configuredColumnCount,
            requiredImageQuality: requiredImageQuality
        )
    }

    private func prepareCurrentImageWindowIfPossible() {
        guard isActive,
              isViewVisible,
              collectionView.window?.windowScene?.activationState
                == .foregroundActive,
              let tokenIndex = currentAnchorTokenIndex() else {
            return
        }
        prepareThumbnailWindow(
            around: tokenIndex,
            direction: lastPrefetchDirection,
            force: true
        )
    }

    private func projectedBrowserTokenRange(
        around tokenIndex: Int,
        direction: DownloadableMediaCache.PrefetchDirection,
        refreshDistance: Int
    ) -> ClosedRange<Int>? {
        guard let browseSnapshot,
              browseSnapshot.itemCount > 0,
              let browserLayout = browserCollectionLayout.browserLayout else {
            return nil
        }
        let lastTokenIndex = browseSnapshot.itemCount - 1
        let targetTokenIndex: Int
        switch direction {
        case .forward:
            let target = tokenIndex.addingReportingOverflow(refreshDistance)
            targetTokenIndex = target.overflow
                ? lastTokenIndex
                : min(target.partialValue, lastTokenIndex)
        case .backward:
            let target = tokenIndex.subtractingReportingOverflow(refreshDistance)
            targetTokenIndex = target.overflow
                ? 0
                : max(target.partialValue, 0)
        }
        guard let targetFrame = browserLayout.itemFrame(at: targetTokenIndex) else {
            return nil
        }
        let projectedContentOffsetY = clampedVerticalContentOffsetY(
            focalGeometry?.contentOffsetY(anchoringFocalY: targetFrame.midY)
                ?? targetFrame.midY - collectionView.bounds.height / 2
        )
        let projectedViewport = CGRect(
            x: collectionView.bounds.minX,
            y: projectedContentOffsetY,
            width: collectionView.bounds.width,
            height: collectionView.bounds.height
        )
        let candidates = browserLayout.candidateItemIndices(
            intersecting: projectedViewport
        )
        guard let first = candidates.first,
              let last = candidates.last else {
            return nil
        }
        return first...last
    }

    private func transitionSelection(tokenIndex: Int) -> MobilePlayerBrowserTransitionSelection? {
        guard let selectedSnapshot = itemSnapshot(tokenIndex: tokenIndex) else { return nil }
        let neighbors = collectionView.indexPathsForVisibleItems
            .map(\.item)
            .filter { $0 != tokenIndex }
            .sorted()
            .compactMap(itemSnapshot(tokenIndex:))
        return MobilePlayerBrowserTransitionSelection(
            selectedSnapshot: selectedSnapshot,
            visibleNeighborSnapshots: neighbors
        )
    }

    private func itemSnapshot(tokenIndex: Int) -> MobilePlayerBrowserItemSnapshot? {
        let indexPath = IndexPath(item: tokenIndex, section: 0)
        guard let cell = collectionView.cellForItem(at: indexPath) as? MobilePlayerCollectionBrowserCell,
              let identity = browserContentIdentity(
                  forTokenIndex: tokenIndex
              ),
              cell.canSelect(representing: identity),
              let pagePosition = browseSnapshot?.pagePosition(forTokenIndex: tokenIndex) else {
            return nil
        }
        let hasLoadedImage = cell.prepareForTransitionSnapshot(tokenIndex: tokenIndex)
        guard let snapshot = cell.transitionSnapshot(
            afterScreenUpdates: hasLoadedImage
        ) else {
            return nil
        }

        return MobilePlayerBrowserItemSnapshot(
            tokenIndex: tokenIndex,
            pagePosition: pagePosition,
            descriptor: cell.descriptor,
            fallbackImageSize: cell.displayedImageSize,
            hasLoadedImage: hasLoadedImage,
            frameInWindow: snapshot.frameInWindow,
            snapshotView: snapshot.view
        )
    }

    private func browseImageSources(
        forTokenIndex tokenIndex: Int
    ) -> CollectionBrowseImageSources? {
        browseSnapshot.flatMap {
            MobileCollectionBrowseMediaResolver.collectionBrowseImageSources(
                snapshot: $0,
                tokenIndex: tokenIndex
            )
        }
    }

    private func browserContentIdentity(
        forTokenIndex tokenIndex: Int
    ) -> MobilePlayerBrowserContentIdentity? {
        guard let browseSnapshot,
              browseSnapshot.pagePosition(forTokenIndex: tokenIndex) != nil else {
            return nil
        }
        return MobilePlayerBrowserContentIdentity(
            collectionId: browseSnapshot.collectionId,
            tokenIndex: tokenIndex
        )
    }

    private func configureBrowserCell(
        _ cell: MobilePlayerCollectionBrowserCell,
        at indexPath: IndexPath,
        requiredImageQuality: CollectionBrowseImageQuality? = nil,
        imageLoadPolicy: MobilePlayerCollectionBrowserCell.ImageLoadPolicy? = nil,
        allowsLocalLargeImageUpgrade: Bool? = nil,
        imageDecodeVariant: DownloadableMediaImageDecodeVariant? = nil
    ) {
        guard let contentIdentity = browserContentIdentity(
            forTokenIndex: indexPath.item
        ) else {
            cell.prepareForGridModePhantomReuse()
            return
        }
        let imageSources = browseImageSources(forTokenIndex: indexPath.item)
        imagePipeline.configure(
            cell: cell,
            tokenIndex: indexPath.item,
            requiredImageQuality: requiredImageQuality,
            imageLoadPolicy: imageLoadPolicy,
            apply: {
                resolvedRequiredImageQuality,
                resolvedImageLoadPolicy,
                resolvedImageDecodeVariant in
                cell.configure(
                    contentIdentity: contentIdentity,
                    itemCount: browseSnapshot?.itemCount ?? 0,
                    imageSources: imageSources,
                    requiredImageQuality: resolvedRequiredImageQuality,
                    missingDescriptorFallbackSpec: layoutAspectState.fallbackSpec,
                    imageLoadPolicy: resolvedImageLoadPolicy,
                    fadesFirstImage: gridModeCoordinator.fadesFirstImage,
                    allowsLocalLargeImageUpgrade: allowsLocalLargeImageUpgrade
                        ?? gridMode.allowsLocalLargeImageUpgrade,
                    imageDecodeVariant: imageDecodeVariant
                        ?? resolvedImageDecodeVariant
                )
            }
        )
    }

    private func reloadVisibleCells() {
        for indexPath in collectionView.indexPathsForVisibleItems {
            guard let cell = collectionView.cellForItem(at: indexPath) as? MobilePlayerCollectionBrowserCell else {
                continue
            }
            configureBrowserCell(cell, at: indexPath)
        }
    }

    private func refreshVisibleCachedImagesIfNeeded(notification: Notification) {
        imagePipeline.handleCacheNotification(notification)
    }

    private var visibleBrowserCells: [MobilePlayerCollectionBrowserCell] {
        collectionView.visibleCells.compactMap { $0 as? MobilePlayerCollectionBrowserCell }
    }

    private func demoteVisibleBrowserImageLoadsIfNeeded() {
        imagePipeline.demoteVisibleImageLoadsIfNeeded()
    }

    private func resumeVisibleBrowserImageLoadsIfNeeded() {
        imagePipeline.resumeVisibleImageLoadsIfNeeded()
    }

#if DEBUG
    var pendingDenseGridImageRefreshCount: Int {
        imagePipeline.pendingDenseGridImageRefreshCount
    }

    var isDenseGridImageDisplayLinkActive: Bool {
        imagePipeline.isDenseGridImageDisplayLinkActive
    }

    var isScrollMotionAnimationTimeoutScheduled: Bool {
        scrollCoordinator.isScrollMotionAnimationTimeoutScheduled
    }

    var isScrollMotionActiveForTesting: Bool {
        isScrollMotionActive
    }

    var hasPendingGridModeGeometryPrewarmForTesting: Bool {
        gridModeCoordinator.lifecycleStateForTesting
            .hasPendingGeometryPrewarm
    }

    func drainDenseGridImageDisplayLinkFrameForTesting() -> Int {
        imagePipeline.drainDenseGridImageDisplayLinkFrameForTesting()
    }

    func replacePendingDenseGridImageRefreshesForTesting(
        tokenIndices: [Int]
    ) {
        imagePipeline.replacePendingDenseGridImageRefreshesForTesting(
            tokenIndices: tokenIndices
        )
    }

    func expireScrollMotionAnimationForTesting() {
        guard isScrollMotionActive else { return }
        endScrollMotion()
        settleAfterApplyingPendingWindowSafeAreaRefresh()
    }

    func resetGridModeGeometryPrewarmingForTesting() {
        gridModeCoordinator.resetGeometryState()
    }

    func flushPendingGridModePinchFrameForTesting() {
        gridModeCoordinator.flushPendingPinchFrameForTesting()
    }

#endif

    func handleGridModePinchForTesting(
        _ recognizer: UIPinchGestureRecognizer
    ) {
        gridModeCoordinator.handleGridModePinchForTesting(recognizer)
    }

}
