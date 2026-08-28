import SwiftUI
import UIKit

private let playerCrossfadeAnimation = Animation.easeInOut(duration: 0.18)

struct MobileCollectionsView: View {
    private struct SessionConfigurationID: Equatable {
        let collectionItems: [MobileCollectionItem]
        let widgetStateID: ObjectIdentifier
        let dependenciesID: UUID
    }

    @Environment(\.displayScale) private var displayScale

    private let collectionItems: [MobileCollectionItem]
    private let widgetLaunchPresentationState:
        WidgetLaunchPresentationState
    private let dependencies:
        MobileCollectionsSessionCoordinator.Dependencies

    @State private var sessionCoordinator:
        MobileCollectionsSessionCoordinator
    @State private var isSearchActive = false
    @State private var collectionSearchQuery = ""

    init(
        collectionItems: [MobileCollectionItem] = MobileCollectionCatalog.allItems,
        widgetLaunchPresentationState: WidgetLaunchPresentationState = .shared,
        dependencies: MobileCollectionsSessionCoordinator.Dependencies = .live
    ) {
        self.collectionItems = collectionItems
        self.widgetLaunchPresentationState =
            widgetLaunchPresentationState
        self.dependencies = dependencies
        _sessionCoordinator = State(initialValue:
            MobileCollectionsSessionCoordinator(
                collectionItems: collectionItems,
                widgetLaunchPresentationState:
                    widgetLaunchPresentationState,
                dependencies: dependencies,
                initialCollectionIdsForPrewarm: {
                    MobileCollectionsGridInitialState
                        .prewarmCollectionIDs(
                            in: collectionItems,
                            limit: 2
                        )
                }
            )
        )
    }

    var body: some View {
        ZStack {
            Color(uiColor: MobilePlayerBackgroundColor.defaultColor)
                .ignoresSafeArea()

            MobileCollectionsNavigationView(
                rootView: collectionsRootView,
                playerConfig: sessionCoordinator.playerConfig,
                presentationTransition:
                    sessionCoordinator.playerPresentationTransition,
                onWillDismissPlayer:
                    sessionCoordinator
                        .resolutionForPendingPresentationRequest,
                onDidPresentPlayer:
                    sessionCoordinator.didPresentPlayer,
                onDismissPlayer: sessionCoordinator.dismissPlayer
            )
            .opacity(
                sessionCoordinator.isReadyToRevealNavigation ? 1 : 0
            )
            .allowsHitTesting(
                sessionCoordinator.isReadyToRevealNavigation
            )
        }
        .ignoresSafeArea()
        .persistentSystemOverlays(.hidden)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            sessionCoordinator.applicationDidBecomeActive()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .playerViewingProgressDidChange)
                .receive(on: RunLoop.main)
        ) { _ in
            sessionCoordinator.viewingProgressDidChange()
        }
        .onChange(of: sessionConfigurationID, initial: true) {
            synchronizeSessionCoordinator()
        }
        .task(id: sessionCoordinator.viewingProgressRefreshID) {
            await sessionCoordinator.refreshViewingProgress(
                id: sessionCoordinator.viewingProgressRefreshID
            )
        }
        .onOpenURL { url in
            _ = sessionCoordinator.handleOpenURL(url)
        }
        .onDisappear {
            sessionCoordinator.cancel()
        }
    }

    private var sessionConfigurationID: SessionConfigurationID {
        SessionConfigurationID(
            collectionItems: collectionItems,
            widgetStateID: ObjectIdentifier(
                widgetLaunchPresentationState
            ),
            dependenciesID: dependencies.id
        )
    }

    private var collectionsRootView: some View {
        ZStack {
            InfiniteCollectionsGridView(
                items: collectionItems,
                progressByCollectionId:
                    sessionCoordinator.viewingProgressByCollectionId,
                viewedToEndCollectionIds:
                    sessionCoordinator.viewedToEndCollectionIds,
                animatesInitialAppearance:
                    sessionCoordinator
                        .shouldAnimateInitialCollectionsAppearance,
                onSelect: didSelectCollectionItem
            )
            .ignoresSafeArea()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isSearchActive {
                    ToolbarItem(placement: .principal) {
                        MobileCollectionsSearchBar(
                            query: $collectionSearchQuery,
                            isFocusSuspended:
                                sessionCoordinator.playerConfig != nil
                        )
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(Strings.cancel) { deactivateSearch() }
                    }
                } else {
                    ToolbarItem(placement: .principal) {}
                    ToolbarItem(placement: .navigationBarLeading) {
                        Menu {
                            Text(Strings.sendFeedback)
                            Button(Strings.github) { UIApplication.shared.open(URL.github) }
                            Button(Strings.mail) { UIApplication.shared.open(URL.mail) }
                            Button(Strings.x) { UIApplication.shared.open(URL.x) }
                            Divider()
                            Button(Strings.rateOnTheAppStore) { UIApplication.shared.open(URL.writeAppStoreReview) }
                            Divider()
                            Button(Strings.changeAppIcon) { didClickToggleAppIcon() }
                        } label: {
                            Images.preferences
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button { activateSearch() } label: {
                            Images.search
                        }
                    }
                }
            }

            if !sessionCoordinator.isPreparingWidgetPlayerPresentation,
               !sessionCoordinator.recentContinueViewingProgresses.isEmpty,
               !isSearchActive {
                GeometryReader { geometry in
                    VStack {
                        Spacer()
                        ContinueViewingPillsScrollView(
                            progresses: Array(
                                sessionCoordinator
                                    .recentContinueViewingProgresses
                                    .prefix(
                                    MobileCollectionsContinueViewingMetrics.maximumVisibleCount
                                    )
                            ),
                            availableWidth: geometry.size.width,
                            horizontalContentInset:
                                MobileCollectionsContinueViewingMetrics.horizontalContentInset,
                            resetID:
                                sessionCoordinator.continueViewingScrollResetID,
                            coverAssetName: coverAssetName(for:),
                            onSelect: { progress in
                                _ = sessionCoordinator
                                    .requestResumeViewing(progress)
                            }
                        )
                        .padding(.bottom, MobileBottomChromeSpacing.continueViewingPadding(forSafeAreaBottom: geometry.safeAreaInsets.bottom))
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .ignoresSafeArea(edges: .bottom)
                }
                .transition(.opacity)
                .zIndex(0.5)
            }

            if isSearchActive {
                MobileCollectionsSearchResultsView(
                    query: collectionSearchQuery,
                    onSelect: didSelectSearchResult
                )
                .transition(.opacity)
                .zIndex(1)
            }
        }
        .persistentSystemOverlays(.hidden)
    }
    
    private func didClickToggleAppIcon() {
        if UIApplication.shared.alternateIconName == nil {
            UIApplication.shared.setAlternateIconName("AppIconLegacy")
        } else {
            UIApplication.shared.setAlternateIconName(nil)
        }
    }

    private func didSelectCollectionItem(_ item: MobileCollectionItem) {
        sessionCoordinator.requestCollectionOpen(collectionId: item.id)
    }

    private func activateSearch() {
        collectionSearchQuery = ""
        MobileCollectionCoverImageCache.shared.prefetch(
            assetNames: collectionItems.prefix(24).map(\.coverAssetName),
            targetSize: CGSize(
                width: MobileCollectionsSearchMetrics.coverThumbnailSize,
                height: MobileCollectionsSearchMetrics.coverThumbnailSize
            ),
            displayScale: displayScale > 0 ? displayScale : UIScreen.main.scale
        )
        withAnimation(playerCrossfadeAnimation) {
            isSearchActive = true
        }
    }

    private func deactivateSearch() {
        withAnimation(playerCrossfadeAnimation) {
            isSearchActive = false
        }
    }

    private func didSelectSearchResult(_ item: MobileCollectionItem) {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        sessionCoordinator.requestCollectionOpen(collectionId: item.id)
    }

    private func coverAssetName(for collectionId: String) -> String {
        collectionItems.first { $0.id == collectionId }?.coverAssetName ?? collectionId
    }

    private func synchronizeSessionCoordinator() {
        sessionCoordinator.update(
            collectionItems: collectionItems,
            widgetLaunchPresentationState:
                widgetLaunchPresentationState,
            dependencies: dependencies,
            initialCollectionIdsForPrewarm: {
                MobileCollectionsGridInitialState
                    .prewarmCollectionIDs(
                        in: collectionItems,
                        limit: 2
                    )
            }
        )
    }
}
