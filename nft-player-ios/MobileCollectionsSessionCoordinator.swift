// ∅ 2026 lil org

import Observation
import SwiftUI

nonisolated protocol MobileCollectionsProgressStoring: Sendable {
    func progress(collectionId: String) async -> MobileViewingProgress?
    func progressSnapshot() async -> PlayerViewingProgressSnapshot
    func prepareContinueViewingUpdate(
        collectionId: String,
        isRemoved: Bool
    ) async -> PlayerContinueViewingUpdate?
    @discardableResult
    func save(_ progress: MobileViewingProgress) async -> Bool
    func applyContinueViewingUpdate(
        _ update: PlayerContinueViewingUpdate
    ) async
}

extension PlayerViewingProgressStore: MobileCollectionsProgressStoring {}

enum PlayerPresentationTransition {
    case animated
    case instant

    var animatesNavigationTransition: Bool {
        switch self {
        case .animated:
            true
        case .instant:
            false
        }
    }
}

@MainActor
@Observable
final class MobileCollectionsSessionCoordinator {
    struct PlayerConfigurationRequest {
        let initialItemId: String?
        let initialTokenId: String?
        let initialTokenIndex: Int?
        let continueViewingCollectionId: String?
        let widgetTokenInsertion: PlayerWidgetTokenInsertion?
    }

    struct Dependencies {
        let id = UUID()
        let progressStore: any MobileCollectionsProgressStoring
        let flushPersistenceUpdates: @MainActor () async -> Void
        let canOpenCollection: (String) -> Bool
        let makeWidgetTokenInsertion: (
            String,
            String,
            MobileViewingProgress?
        ) -> PlayerWidgetTokenInsertion?
        let preparePlayerConfig: (PlayerConfigurationRequest) -> MobilePlayerConfig
        let schedulePlayerPrewarm: (MobileViewingProgress?, [String]) -> Void
        let emitSelectionHaptic: () -> Void

        static let live = Dependencies(
            progressStore: MobileViewingProgressStore.shared,
            flushPersistenceUpdates: {
                await PlayerPersistenceUpdates.flush()
            },
            canOpenCollection: { collectionId in
                MobileCollectionCatalog.canOpenCollection(
                    specificCollectionId: collectionId
                )
            },
            makeWidgetTokenInsertion: { collectionId, tokenId, progress in
                MobileCollectionCatalog.widgetTokenInsertion(
                    collectionId: collectionId,
                    widgetTokenId: tokenId,
                    progress: progress
                )
            },
            preparePlayerConfig: { request in
                MobilePlayerPrewarmer.preparedConfig(
                    initialItemId: request.initialItemId,
                    initialTokenId: request.initialTokenId,
                    initialTokenIndex: request.initialTokenIndex,
                    continueViewingCollectionId:
                        request.continueViewingCollectionId,
                    widgetTokenInsertion: request.widgetTokenInsertion
                )
            },
            schedulePlayerPrewarm: { continueViewingProgress, collectionIds in
                MobilePlayerPrewarmer.scheduleAfterLaunch(
                    continueViewingProgress: continueViewingProgress,
                    initialCollectionIds: collectionIds
                )
            },
            emitSelectionHaptic: {
                Haptic.selectionChanged()
            }
        )
    }

    private struct WidgetPlayerHandoff {
        let playerConfigID: UUID
        let request: WidgetLaunchPresentationState.Request
    }

    private var visibleCollectionIds: Set<String>
    private var widgetLaunchPresentationState: WidgetLaunchPresentationState
    private var dependencies: Dependencies
    private var initialCollectionIdsForPrewarm: () -> [String]
    private let playerPresentationGate = PlayerPresentationRequestGate()

    private(set) var playerConfig: MobilePlayerConfig?
    private(set) var playerPresentationTransition:
        PlayerPresentationTransition = .animated
    private(set) var viewingProgressSnapshot =
        PlayerViewingProgressSnapshot.empty
    private(set) var hasLoadedViewingProgress = false
    private(set) var continueViewingScrollResetID = 0
    private(set) var viewingProgressRefreshID = 0

    private var shouldResetScrollAfterViewingProgressRefresh = true
    private var shouldPrewarmAfterViewingProgressRefresh = true
    private var pendingWidgetHandoffRequest:
        WidgetLaunchPresentationState.Request?
    private var widgetPlayerHandoff: WidgetPlayerHandoff?

    init(
        collectionItems: [MobileCollectionItem],
        widgetLaunchPresentationState: WidgetLaunchPresentationState,
        dependencies: Dependencies = .live,
        initialCollectionIdsForPrewarm: @escaping () -> [String]
    ) {
        self.visibleCollectionIds = Set(collectionItems.map(\.id))
        self.widgetLaunchPresentationState = widgetLaunchPresentationState
        self.dependencies = dependencies
        self.initialCollectionIdsForPrewarm =
            initialCollectionIdsForPrewarm
    }

    var viewingProgressByCollectionId: [String: Int] {
        viewingProgressSnapshot.percentagesByCollectionId
    }

    var viewedToEndCollectionIds: Set<String> {
        viewingProgressSnapshot.viewedToEndCollectionIds
    }

    var recentContinueViewingProgresses: [MobileViewingProgress] {
        viewingProgressSnapshot.recentContinueViewingProgresses.filter {
            progress in
            visibleCollectionIds.contains(progress.collectionId)
                && dependencies.canOpenCollection(progress.collectionId)
        }
    }

    var isPreparingWidgetPlayerPresentation: Bool {
        widgetLaunchPresentationState.isPreparingWidgetPlayerPresentation
    }

    var shouldAnimateInitialCollectionsAppearance: Bool {
        widgetLaunchPresentationState
            .shouldAnimateInitialCollectionsAppearance
    }

    var isReadyToRevealNavigation: Bool {
        (hasLoadedViewingProgress || playerConfig != nil)
            && !isPreparingWidgetPlayerPresentation
    }

    func update(
        collectionItems: [MobileCollectionItem],
        widgetLaunchPresentationState: WidgetLaunchPresentationState,
        dependencies: Dependencies,
        initialCollectionIdsForPrewarm: @escaping () -> [String]
    ) {
        let visibleCollectionIds = Set(collectionItems.map(\.id))
        let refreshesProgress = self.visibleCollectionIds
            != visibleCollectionIds
            || self.dependencies.id != dependencies.id
        let changesWidgetState = self.widgetLaunchPresentationState
            !== widgetLaunchPresentationState
        if refreshesProgress || changesWidgetState {
            let pendingWidgetHandoffRequest =
                pendingWidgetHandoffRequest
            playerPresentationGate.cancel()
            finishPendingWidgetHandoff(pendingWidgetHandoffRequest)
        }
        if changesWidgetState {
            self.widgetLaunchPresentationState
                .cancelAllWidgetPlayerHandoffs()
            widgetPlayerHandoff = nil
        }
        self.visibleCollectionIds = visibleCollectionIds
        self.widgetLaunchPresentationState = widgetLaunchPresentationState
        self.dependencies = dependencies
        self.initialCollectionIdsForPrewarm =
            initialCollectionIdsForPrewarm
        if refreshesProgress {
            requestViewingProgressRefresh(
                resetScroll: true,
                prewarm: true
            )
        }
    }

    @discardableResult
    func requestCollectionOpen(
        collectionId: String,
        transition: PlayerPresentationTransition = .animated
    ) -> Task<Bool, Never> {
        let request = playerPresentationGate.begin()
        return Task { @MainActor in
            return await self.openCollection(
                collectionId: collectionId,
                transition: transition,
                request: request
            )
        }
    }

    @discardableResult
    func requestResumeViewing(
        _ progress: MobileViewingProgress
    ) -> Task<Bool, Never> {
        requestCollectionOpen(collectionId: progress.collectionId)
    }

    @discardableResult
    func handleOpenURL(_ url: URL) -> Task<Void, Never>? {
        guard let deepLink = WidgetDeepLink(url: url),
              case let .collection(collectionId, tokenId) = deepLink,
              visibleCollectionIds.contains(collectionId) else {
            widgetLaunchPresentationState.finishWidgetPlayerHandoff(for: url)
            return nil
        }

        let request = playerPresentationGate.begin()
        widgetPlayerHandoff = nil
        let handoffRequest = widgetLaunchPresentationState
            .beginWidgetPlayerHandoff(for: url)
        pendingWidgetHandoffRequest = handoffRequest
        return Task { @MainActor in
            let didAcceptPresentation: Bool
            if let tokenId {
                didAcceptPresentation = await self.openWidgetToken(
                    collectionId: collectionId,
                    tokenId: tokenId,
                    request: request,
                    widgetHandoffRequest: handoffRequest
                )
            } else {
                didAcceptPresentation = await self.openCollection(
                    collectionId: collectionId,
                    transition: .instant,
                    request: request,
                    widgetHandoffRequest: handoffRequest
                )
            }
            if !didAcceptPresentation {
                self.finishPendingWidgetHandoff(
                    handoffRequest
                )
            }
        }
    }

    func applicationDidBecomeActive() {
        requestViewingProgressRefresh(resetScroll: true, prewarm: true)
    }

    func viewingProgressDidChange() {
        guard playerConfig == nil else { return }
        requestViewingProgressRefresh()
    }

    func refreshViewingProgress(id refreshID: Int) async {
        let shouldResetScroll =
            shouldResetScrollAfterViewingProgressRefresh
        let shouldPrewarm =
            shouldPrewarmAfterViewingProgressRefresh
        let previousLeadingCollectionId =
            recentContinueViewingProgresses.first?.collectionId
        let snapshot = await dependencies.progressStore.progressSnapshot()
        guard !Task.isCancelled,
              refreshID == viewingProgressRefreshID else {
            return
        }

        viewingProgressSnapshot = snapshot
        shouldResetScrollAfterViewingProgressRefresh = false
        shouldPrewarmAfterViewingProgressRefresh = false

        if shouldResetScroll
            || (playerConfig == nil
                && previousLeadingCollectionId
                    != recentContinueViewingProgresses.first?.collectionId) {
            continueViewingScrollResetID += 1
        }
        hasLoadedViewingProgress = true
        if shouldPrewarm {
            dependencies.schedulePlayerPrewarm(
                recentContinueViewingProgresses.first,
                initialCollectionIdsForPrewarm()
            )
        }
    }

    func resolutionForPendingPresentationRequest()
        -> (@MainActor (Bool) -> Void)? {
        playerPresentationGate.resolutionForPendingRequest()
    }

    func didPresentPlayer(_ config: MobilePlayerConfig) {
        guard let widgetPlayerHandoff,
              widgetPlayerHandoff.playerConfigID == config.id else {
            return
        }
        self.widgetPlayerHandoff = nil
        widgetLaunchPresentationState.finishWidgetPlayerHandoff(
            widgetPlayerHandoff.request
        )
    }

    func dismissPlayer(_ config: MobilePlayerConfig) {
        guard playerConfig?.id == config.id else { return }
        playerPresentationTransition = .animated
        withAnimation(playerCrossfadeAnimation) {
            playerConfig = nil
        }
        requestViewingProgressRefresh(resetScroll: true)
    }

    func cancel() {
        playerPresentationGate.cancel()
        pendingWidgetHandoffRequest = nil
        widgetPlayerHandoff = nil
        widgetLaunchPresentationState.cancelAllWidgetPlayerHandoffs()
    }

    private func requestViewingProgressRefresh(
        resetScroll: Bool = false,
        prewarm: Bool = false
    ) {
        shouldResetScrollAfterViewingProgressRefresh =
            shouldResetScrollAfterViewingProgressRefresh || resetScroll
        shouldPrewarmAfterViewingProgressRefresh =
            shouldPrewarmAfterViewingProgressRefresh || prewarm
        viewingProgressRefreshID &+= 1
    }

    private func openCollection(
        collectionId: String,
        transition: PlayerPresentationTransition,
        request: PlayerPresentationRequestGate.Request,
        widgetHandoffRequest: WidgetLaunchPresentationState.Request? = nil
    ) async -> Bool {
        await dependencies.flushPersistenceUpdates()
        guard playerPresentationGate.isPending(request) else { return false }
        let progress = await dependencies.progressStore.progress(
            collectionId: collectionId
        )
        guard playerPresentationGate.isPending(request) else { return false }
        if let progress {
            return await openPlayer(
                initialItemId: progress.collectionId,
                initialTokenId: progress.tokenId,
                initialTokenIndex: progress.tokenIndex,
                continueViewingCollectionId: progress.collectionId,
                transition: transition,
                request: request,
                widgetHandoffRequest: widgetHandoffRequest
            )
        }
        return await openPlayer(
            initialItemId: collectionId,
            continueViewingCollectionId: collectionId,
            transition: transition,
            request: request,
            widgetHandoffRequest: widgetHandoffRequest
        )
    }

    private func openWidgetToken(
        collectionId: String,
        tokenId: String,
        request: PlayerPresentationRequestGate.Request,
        widgetHandoffRequest: WidgetLaunchPresentationState.Request?
    ) async -> Bool {
        await dependencies.flushPersistenceUpdates()
        guard playerPresentationGate.isPending(request) else { return false }
        let progress = await dependencies.progressStore.progress(
            collectionId: collectionId
        )
        guard playerPresentationGate.isPending(request) else { return false }
        guard let widgetTokenInsertion =
            dependencies.makeWidgetTokenInsertion(
                collectionId,
                tokenId,
                progress
            ) else {
            return await openCollection(
                collectionId: collectionId,
                transition: .instant,
                request: request,
                widgetHandoffRequest: widgetHandoffRequest
            )
        }

        guard playerPresentationGate.isPending(request) else { return false }
        return await openPlayer(
            initialItemId: collectionId,
            continueViewingCollectionId: collectionId,
            widgetTokenInsertion: widgetTokenInsertion,
            anchorProgress: widgetTokenInsertion.automaticAnchorProgress(),
            transition: .instant,
            request: request,
            widgetHandoffRequest: widgetHandoffRequest
        )
    }

    private func openPlayer(
        initialItemId: String,
        initialTokenId: String? = nil,
        initialTokenIndex: Int? = nil,
        continueViewingCollectionId: String,
        widgetTokenInsertion: PlayerWidgetTokenInsertion? = nil,
        anchorProgress: MobileViewingProgress? = nil,
        transition: PlayerPresentationTransition,
        request: PlayerPresentationRequestGate.Request,
        widgetHandoffRequest: WidgetLaunchPresentationState.Request? = nil
    ) async -> Bool {
        guard playerPresentationGate.isPending(request) else { return false }
        guard let continueViewingUpdate = await dependencies.progressStore
            .prepareContinueViewingUpdate(
                collectionId: continueViewingCollectionId,
                isRemoved: false
            ),
              playerPresentationGate.isPending(request) else {
            return false
        }
        let config = dependencies.preparePlayerConfig(
            PlayerConfigurationRequest(
                initialItemId: initialItemId,
                initialTokenId: initialTokenId,
                initialTokenIndex: initialTokenIndex,
                continueViewingCollectionId: continueViewingCollectionId,
                widgetTokenInsertion: widgetTokenInsertion
            )
        )
        let progressStore = dependencies.progressStore
        let widgetLaunchPresentationState = widgetLaunchPresentationState
        return playerPresentationGate.commit(
            request,
            present: { [weak self] in
                guard let self else { return }
                if let widgetHandoffRequest {
                    if pendingWidgetHandoffRequest
                        == widgetHandoffRequest {
                        pendingWidgetHandoffRequest = nil
                    }
                    widgetPlayerHandoff = WidgetPlayerHandoff(
                        playerConfigID: config.id,
                        request: widgetHandoffRequest
                    )
                }
                switch transition {
                case .animated:
                    withAnimation(playerCrossfadeAnimation) {
                        playerPresentationTransition = transition
                        playerConfig = config
                    }
                case .instant:
                    var transaction = Transaction(animation: nil)
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        playerPresentationTransition = transition
                        playerConfig = config
                    }
                }
                dependencies.emitSelectionHaptic()
            },
            persist: {
                if let anchorProgress {
                    _ = await progressStore.save(anchorProgress)
                }
                await progressStore.applyContinueViewingUpdate(
                    continueViewingUpdate
                )
            },
            discard: { [weak self] in
                guard let self else {
                    widgetLaunchPresentationState
                        .finishWidgetPlayerHandoff(
                            widgetHandoffRequest
                        )
                    return
                }
                finishPendingWidgetHandoff(widgetHandoffRequest)
            }
        )
    }

    private func finishPendingWidgetHandoff(
        _ request: WidgetLaunchPresentationState.Request?
    ) {
        guard let request,
              pendingWidgetHandoffRequest == request else {
            return
        }
        pendingWidgetHandoffRequest = nil
        widgetLaunchPresentationState.finishWidgetPlayerHandoff(
            request
        )
    }
}

private let playerCrossfadeAnimation =
    Animation.easeInOut(duration: 0.18)
