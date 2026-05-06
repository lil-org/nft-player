import SwiftUI
import UIKit

private let playerCrossfadeAnimation = Animation.easeInOut(duration: 0.18)

private enum InfiniteCollectionsLoop {
    private static let repetitionCount = 31
    private static let middleRepetition = repetitionCount / 2
    private static let recenterThreshold = 5
    private static let initialSourceOffset = 12

    static func virtualItemCount(itemCount: Int) -> Int {
        repetitionCount * itemCount
    }

    static func repetition(for virtualIndex: Int, itemCount: Int) -> Int {
        virtualIndex / itemCount
    }

    static func sourceIndex(for virtualIndex: Int, itemCount: Int) -> Int {
        virtualIndex % itemCount
    }

    static func centeredIndex(sourceIndex: Int, itemCount: Int) -> Int {
        middleRepetition * itemCount + sourceIndex
    }

    static func initialScrollPosition(itemCount: Int) -> Int? {
        guard itemCount > 0 else { return nil }
        return centeredIndex(sourceIndex: initialSourceOffset % itemCount, itemCount: itemCount)
    }

    static func shouldRecenter(repetition: Int) -> Bool {
        repetition <= recenterThreshold || repetition >= repetitionCount - recenterThreshold
    }
}

struct MobileCollectionsView: View {
    private let suggestedItems = TokenGenerator.allGenerativeSuggestedItems
    @State private var playerConfig: MobilePlayerConfig?
    @State private var viewingProgressByCollectionId: [String: Int]
    @State private var latestIncompleteProgress: MobileViewingProgress?
    
    init() {
        let progressSnapshot = MobileViewingProgressStore.progressSnapshot()
        _viewingProgressByCollectionId = State(initialValue: progressSnapshot.percentagesByCollectionId)
        _latestIncompleteProgress = State(initialValue: progressSnapshot.latestIncompleteProgress)

        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundColor = .clear
        appearance.backgroundEffect = nil
        appearance.shadowColor = .clear
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
        UINavigationBar.appearance().compactScrollEdgeAppearance = appearance
    }
    
    var body: some View {
        ZStack {
            NavigationStack {
                InfiniteCollectionsGridView(
                    items: suggestedItems,
                    progressByCollectionId: viewingProgressByCollectionId,
                    onSelect: didSelectSuggestedItem
                )
                .ignoresSafeArea()
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {}
                }
                .toolbar {
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
                        Button { showShuffledCollectionPlayer() } label: {
                            Images.shuffle
                        }
                    }
                }
            }

            if playerConfig == nil, let latestIncompleteProgress {
                VStack {
                    Spacer()
                    ContinueViewingButton(progress: latestIncompleteProgress) {
                        resumeViewing(latestIncompleteProgress)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 18)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(0.5)
            }

            if let playerConfig {
                PlayerNavigationOverlay(config: playerConfig) {
                    dismissPlayer(playerConfig)
                }
                .ignoresSafeArea()
                .persistentSystemOverlays(.hidden)
                .zIndex(1)
                .id(playerConfig.id)
                .transition(.opacity)
            }
        }
        .persistentSystemOverlays(.hidden)
        .onAppear(perform: refreshViewingProgress)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            refreshViewingProgress()
        }
    }
    
    private func didClickToggleAppIcon() {
        if UIApplication.shared.alternateIconName == nil {
            UIApplication.shared.setAlternateIconName("AppIconLegacy")
        } else {
            UIApplication.shared.setAlternateIconName(nil)
        }
    }
    
    private func didSelectSuggestedItem(_ item: SuggestedItem) {
        if let progress = MobileViewingProgressStore.progress(collectionId: item.id) {
            resumeViewing(progress)
            return
        }

        withAnimation(playerCrossfadeAnimation) {
            playerConfig = MobilePlayerConfig(initialItemId: item.id)
        }
        Haptic.selectionChanged()
    }
    
    private func showShuffledCollectionPlayer() {
        withAnimation(playerCrossfadeAnimation) {
            playerConfig = MobilePlayerConfig(initialItemId: nil)
        }
        Haptic.selectionChanged()
    }

    private func resumeViewing(_ progress: MobileViewingProgress) {
        withAnimation(playerCrossfadeAnimation) {
            playerConfig = MobilePlayerConfig(initialItemId: progress.collectionId, initialTokenId: progress.tokenId)
        }
        Haptic.selectionChanged()
    }

    private func dismissPlayer(_ config: MobilePlayerConfig) {
        guard playerConfig?.id == config.id else { return }
        withAnimation(playerCrossfadeAnimation) {
            playerConfig = nil
            refreshViewingProgress()
        }
    }

    private func refreshViewingProgress() {
        let progressSnapshot = MobileViewingProgressStore.progressSnapshot()
        viewingProgressByCollectionId = progressSnapshot.percentagesByCollectionId
        latestIncompleteProgress = progressSnapshot.latestIncompleteProgress
    }
    
}

private struct InfiniteCollectionsGridView: UIViewRepresentable {
    let items: [SuggestedItem]
    let progressByCollectionId: [String: Int]
    let onSelect: (SuggestedItem) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(items: [], progressByCollectionId: [:], onSelect: onSelect)
    }

    func makeUIView(context: Context) -> InfiniteCollectionsGridContainerView {
        let containerView = InfiniteCollectionsGridContainerView()
        containerView.update(items: items, progressByCollectionId: progressByCollectionId, coordinator: context.coordinator)
        return containerView
    }

    func updateUIView(_ containerView: InfiniteCollectionsGridContainerView, context: Context) {
        context.coordinator.onSelect = onSelect
        containerView.update(items: items, progressByCollectionId: progressByCollectionId, coordinator: context.coordinator)
    }

    final class Coordinator: NSObject, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
        var items: [SuggestedItem]
        var progressByCollectionId: [String: Int]
        var onSelect: (SuggestedItem) -> Void
        private var isRecentering = false

        enum UpdateResult {
            case noChange
            case progressOnly
            case itemsChanged
        }

        init(items: [SuggestedItem], progressByCollectionId: [String: Int], onSelect: @escaping (SuggestedItem) -> Void) {
            self.items = items
            self.progressByCollectionId = progressByCollectionId
            self.onSelect = onSelect
        }

        func update(items: [SuggestedItem], progressByCollectionId: [String: Int]) -> UpdateResult {
            let itemsChanged = self.items != items
            let progressChanged = self.progressByCollectionId != progressByCollectionId
            guard itemsChanged || progressChanged else { return .noChange }
            self.items = items
            self.progressByCollectionId = progressByCollectionId
            return itemsChanged ? .itemsChanged : .progressOnly
        }

        func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
            InfiniteCollectionsLoop.virtualItemCount(itemCount: items.count)
        }

        func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: CollectionGridCell.reuseIdentifier, for: indexPath)
            guard let gridCell = cell as? CollectionGridCell else { return cell }
            let item = item(for: indexPath.item)
            gridCell.configure(item: item, progressPercent: progressByCollectionId[item.id])
            return gridCell
        }

        func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
            onSelect(item(for: indexPath.item))
        }

        func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
            let minimumItemWidth: CGFloat = UIDevice.current.userInterfaceIdiom == .pad ? 130 : 77
            let columns = max(Int(collectionView.bounds.width / minimumItemWidth), 1)
            let itemWidth = collectionView.bounds.width / CGFloat(columns)
            return CGSize(width: itemWidth, height: itemWidth)
        }

        func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumInteritemSpacingForSectionAt section: Int) -> CGFloat {
            0
        }

        func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumLineSpacingForSectionAt section: Int) -> CGFloat {
            0
        }

        func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
            let item = item(for: indexPath.item)
            return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
                let playAction = UIAction(title: Strings.play, image: UIImage(systemName: "play")) { _ in
                    self?.onSelect(item)
                }
                return UIMenu(title: item.name, children: [playAction])
            }
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard !isRecentering,
                  let collectionView = scrollView as? UICollectionView,
                  !items.isEmpty,
                  let topIndexPath = collectionView.indexPathsForVisibleItems.min(by: { $0.item < $1.item }) else {
                return
            }

            let itemCount = items.count
            let repetition = InfiniteCollectionsLoop.repetition(for: topIndexPath.item, itemCount: itemCount)
            guard InfiniteCollectionsLoop.shouldRecenter(repetition: repetition),
                  let topAttributes = collectionView.layoutAttributesForItem(at: topIndexPath) else {
                return
            }

            let sourceIndex = InfiniteCollectionsLoop.sourceIndex(for: topIndexPath.item, itemCount: itemCount)
            let targetIndexPath = IndexPath(item: InfiniteCollectionsLoop.centeredIndex(sourceIndex: sourceIndex, itemCount: itemCount), section: 0)
            collectionView.layoutIfNeeded()
            guard let targetAttributes = collectionView.layoutAttributesForItem(at: targetIndexPath) else { return }

            isRecentering = true
            let offsetWithinTopItem = collectionView.contentOffset.y - topAttributes.frame.minY
            collectionView.setContentOffset(
                CGPoint(x: collectionView.contentOffset.x, y: targetAttributes.frame.minY + offsetWithinTopItem),
                animated: false
            )
            isRecentering = false
        }

        func setInitialScrollPosition(in collectionView: UICollectionView) {
            guard !items.isEmpty,
                  let targetIndex = InfiniteCollectionsLoop.initialScrollPosition(itemCount: items.count) else {
                return
            }

            collectionView.layoutIfNeeded()
            let targetIndexPath = IndexPath(item: targetIndex, section: 0)
            guard let targetAttributes = collectionView.layoutAttributesForItem(at: targetIndexPath) else {
                collectionView.scrollToItem(at: targetIndexPath, at: .top, animated: false)
                return
            }

            isRecentering = true
            collectionView.setContentOffset(CGPoint(x: 0, y: targetAttributes.frame.minY), animated: false)
            isRecentering = false
        }

        func updateVisibleProgressCells(in collectionView: UICollectionView) {
            collectionView.indexPathsForVisibleItems.forEach { indexPath in
                guard let gridCell = collectionView.cellForItem(at: indexPath) as? CollectionGridCell else { return }
                let item = item(for: indexPath.item)
                gridCell.configure(item: item, progressPercent: progressByCollectionId[item.id])
            }
        }

        private func item(for virtualIndex: Int) -> SuggestedItem {
            items[InfiniteCollectionsLoop.sourceIndex(for: virtualIndex, itemCount: items.count)]
        }
    }
}

private final class InfiniteCollectionsGridContainerView: UIView {
    private let collectionView: UICollectionView
    private weak var coordinator: InfiniteCollectionsGridView.Coordinator?
    private var didSetInitialScrollPosition = false
    private var previousBoundsSize = CGSize.zero

    override init(frame: CGRect) {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumInteritemSpacing = 0
        layout.minimumLineSpacing = 0
        layout.sectionInset = .zero

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(frame: frame)

        backgroundColor = .clear
        collectionView.backgroundColor = .clear
        collectionView.showsVerticalScrollIndicator = false
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.alwaysBounceVertical = true
        collectionView.register(CollectionGridCell.self, forCellWithReuseIdentifier: CollectionGridCell.reuseIdentifier)
        addSubview(collectionView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(items: [SuggestedItem], progressByCollectionId: [String: Int], coordinator: InfiniteCollectionsGridView.Coordinator) {
        self.coordinator = coordinator
        collectionView.dataSource = coordinator
        collectionView.delegate = coordinator

        switch coordinator.update(items: items, progressByCollectionId: progressByCollectionId) {
        case .itemsChanged:
            didSetInitialScrollPosition = false
            collectionView.reloadData()
        case .progressOnly:
            coordinator.updateVisibleProgressCells(in: collectionView)
        case .noChange:
            break
        }

        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        collectionView.frame = bounds
        if previousBoundsSize != bounds.size {
            previousBoundsSize = bounds.size
            collectionView.collectionViewLayout.invalidateLayout()
        }

        guard !didSetInitialScrollPosition,
              bounds.width > 0,
              bounds.height > 0,
              collectionView.numberOfItems(inSection: 0) > 0 else {
            return
        }

        coordinator?.setInitialScrollPosition(in: collectionView)
        didSetInitialScrollPosition = true
    }
}

private final class CollectionGridCell: UICollectionViewCell {
    static let reuseIdentifier = "CollectionGridCell"

    private let imageView = UIImageView()
    private let titleLabel = GridTitleLabel()
    private let progressLabel = GridTitleLabel()

    override init(frame: CGRect) {
        super.init(frame: frame)

        clipsToBounds = false
        contentView.clipsToBounds = false
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        contentView.addSubview(imageView)

        titleLabel.font = .systemFont(ofSize: 9, weight: .regular)
        titleLabel.textColor = .white
        titleLabel.numberOfLines = 2
        titleLabel.textAlignment = .left
        titleLabel.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        titleLabel.layer.cornerRadius = 3
        titleLabel.clipsToBounds = true
        contentView.addSubview(titleLabel)

        progressLabel.font = .systemFont(ofSize: 9, weight: .semibold)
        progressLabel.textColor = .white
        progressLabel.numberOfLines = 1
        progressLabel.textAlignment = .center
        progressLabel.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        progressLabel.layer.cornerRadius = 3
        progressLabel.clipsToBounds = true
        contentView.addSubview(progressLabel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageView.image = nil
        titleLabel.text = nil
        progressLabel.text = nil
        progressLabel.isHidden = true
    }

    func configure(item: SuggestedItem, progressPercent: Int?) {
        imageView.image = UIImage(named: item.id)
        titleLabel.text = item.name
        if let progressPercent, progressPercent > 0 {
            progressLabel.text = Strings.percent(progressPercent)
            progressLabel.isHidden = false
        } else {
            progressLabel.text = nil
            progressLabel.isHidden = true
        }
        accessibilityLabel = item.name
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        imageView.frame = contentView.bounds.insetBy(dx: -0.5, dy: -0.5)

        let maximumLabelWidth = max(contentView.bounds.width - 8, 0)
        let maximumLabelSize = CGSize(width: maximumLabelWidth, height: CGFloat.greatestFiniteMagnitude)
        let labelSize = titleLabel.sizeThatFits(maximumLabelSize)
        let labelWidth = min(maximumLabelWidth, ceil(labelSize.width))
        let labelHeight = min(ceil(labelSize.height), 28)
        titleLabel.frame = CGRect(
            x: 4,
            y: contentView.bounds.height - labelHeight - 3,
            width: labelWidth,
            height: labelHeight
        )

        if !progressLabel.isHidden {
            let progressSize = progressLabel.sizeThatFits(CGSize(width: 42, height: 16))
            let progressWidth = min(max(ceil(progressSize.width), 28), 44)
            progressLabel.frame = CGRect(
                x: contentView.bounds.width - progressWidth - 4,
                y: 4,
                width: progressWidth,
                height: 15
            )
        }
    }
}

private final class GridTitleLabel: UILabel {
    private let textInsets = UIEdgeInsets(top: 0, left: 1, bottom: 0, right: 1)

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: textInsets))
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let adjustedSize = CGSize(
            width: max(size.width - textInsets.left - textInsets.right, 0),
            height: max(size.height - textInsets.top - textInsets.bottom, 0)
        )
        let measuredSize = super.sizeThatFits(adjustedSize)
        return CGSize(
            width: measuredSize.width + textInsets.left + textInsets.right,
            height: measuredSize.height + textInsets.top + textInsets.bottom
        )
    }
}

private struct ContinueViewingButton: View {
    let progress: MobileViewingProgress
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Images.play
                    .font(.subheadline.weight(.bold))

                VStack(alignment: .leading, spacing: 2) {
                    Text(Strings.continueViewing)
                        .font(.caption.weight(.semibold))
                    Text(progress.collectionName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                }

                Spacer(minLength: 12)

                Text(Strings.percent(progress.percent))
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background {
                ProgressCapsuleBackground(progress: progress.fraction, isInteractive: true)
            }
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct PlayerNavigationOverlay: UIViewControllerRepresentable {

    let config: MobilePlayerConfig
    let onDismiss: () -> Void

    func makeUIViewController(context: Context) -> PlayerOverlayViewController {
        let chrome = MobilePlayerChromeController()
        let playerViewController = makeMobilePlayerViewController(config: config, onDismiss: onDismiss, chrome: chrome)
        let navigationController = PlayerNavigationController(rootViewController: playerViewController)
        navigationController.view.backgroundColor = .clear
        navigationController.view.isOpaque = false
        navigationController.navigationBar.isTranslucent = true
        navigationController.interactivePopGestureRecognizer?.isEnabled = false
        navigationController.setNavigationBarHidden(false, animated: false)

        return PlayerOverlayViewController(
            navigationController: navigationController,
            chrome: chrome,
            onDismiss: onDismiss
        )
    }

    func updateUIViewController(_ overlayViewController: PlayerOverlayViewController, context: Context) {
        overlayViewController.onDismiss = onDismiss
    }

}

private func makeMobilePlayerViewController(
    config: MobilePlayerConfig,
    onDismiss: @escaping () -> Void,
    chrome: MobilePlayerChromeController
) -> UIHostingController<MobilePlayerView> {
    let playerViewController = UIHostingController(rootView: MobilePlayerView(config: config, onDismiss: onDismiss, chrome: chrome))
    playerViewController.view.backgroundColor = .clear
    playerViewController.view.isOpaque = false
    return playerViewController
}

private final class PlayerNavigationController: UINavigationController {

    override var childForStatusBarHidden: UIViewController? {
        topViewController
    }

    override var childForStatusBarStyle: UIViewController? {
        topViewController
    }

}

private final class PlayerOverlayViewController: UIViewController, UIGestureRecognizerDelegate {

    let playerNavigationController: UINavigationController
    let chrome: MobilePlayerChromeController
    var onDismiss: () -> Void

    private lazy var dismissPan = UIPanGestureRecognizer(target: self, action: #selector(handleDismissPan(_:)))
    private lazy var controlsPan = UIPanGestureRecognizer(target: self, action: #selector(handleControlsPan(_:)))
    private let dimmingView = UIView()
    private var configuredScrollPanGestures = Set<ObjectIdentifier>()
    private var isDismissing = false
    private var dismissPanMode = DismissPanMode.dismiss

    private enum DismissPanMode {
        case dismiss
        case hideControls
    }

    init(
        navigationController: UINavigationController,
        chrome: MobilePlayerChromeController,
        onDismiss: @escaping () -> Void
    ) {
        self.playerNavigationController = navigationController
        self.chrome = chrome
        self.onDismiss = onDismiss
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("yo")
    }

    override var childForStatusBarHidden: UIViewController? {
        playerNavigationController
    }

    override var childForStatusBarStyle: UIViewController? {
        playerNavigationController
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .clear
        view.isOpaque = false

        dimmingView.backgroundColor = .black
        dimmingView.alpha = 1
        view.addSubview(dimmingView)
        dimmingView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            dimmingView.topAnchor.constraint(equalTo: view.topAnchor),
            dimmingView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            dimmingView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dimmingView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        addChild(playerNavigationController)
        view.addSubview(playerNavigationController.view)
        playerNavigationController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            playerNavigationController.view.topAnchor.constraint(equalTo: view.topAnchor),
            playerNavigationController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            playerNavigationController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            playerNavigationController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        playerNavigationController.didMove(toParent: self)

        dismissPan.delegate = self
        dismissPan.cancelsTouchesInView = false
        view.addGestureRecognizer(dismissPan)

        controlsPan.delegate = self
        controlsPan.cancelsTouchesInView = false
        view.addGestureRecognizer(controlsPan)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        configurePagingScrollViews()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        configurePagingScrollViews()
    }

    private func configurePagingScrollViews() {
        playerNavigationController.view
            .allSubviews(ofType: UIScrollView.self)
            .forEach { scrollView in
                let panGestureId = ObjectIdentifier(scrollView.panGestureRecognizer)
                if !configuredScrollPanGestures.contains(panGestureId) {
                    scrollView.panGestureRecognizer.require(toFail: dismissPan)
                    configuredScrollPanGestures.insert(panGestureId)
                }
                scrollView.hideAutomaticScrollEdgeEffects()
            }
    }

    @objc private func handleDismissPan(_ gesture: UIPanGestureRecognizer) {
        guard !isDismissing else { return }

        let translation = gesture.translation(in: view)
        let clampedY = max(0, translation.y)

        switch gesture.state {
        case .began:
            if chrome.showControls {
                dismissPanMode = .hideControls
                chrome.setControlsVisible(false)
                return
            }

            dismissPanMode = .dismiss
            playerNavigationController.view.layer.removeAllAnimations()
            dimmingView.layer.removeAllAnimations()

        case .changed:
            guard dismissPanMode == .dismiss else { return }
            let progress = min(clampedY / MobilePlayerGestureTuning.dismissProgressDistance, 1)
            applyDismissPresentation(offsetY: clampedY, progress: progress)

        case .ended:
            if dismissPanMode == .dismiss {
                finishDismissGesture(translation: translation, velocity: gesture.velocity(in: view))
            }

        case .cancelled, .failed:
            if dismissPanMode == .dismiss {
                resetDismissTransform()
            }

        default:
            break
        }
    }

    @objc private func handleControlsPan(_ gesture: UIPanGestureRecognizer) {
        guard !isDismissing else { return }

        switch gesture.state {
        case .began, .changed:
            let translation = gesture.translation(in: view)
            if translation.y < -8 {
                chrome.setControlsVisible(true)
            }
        default:
            break
        }
    }

    private func finishDismissGesture(translation: CGPoint, velocity: CGPoint) {
        let clampedY = max(0, translation.y)
        let projectedY = clampedY + max(velocity.y, 0) * MobilePlayerGestureTuning.dismissVelocityProjectionDuration
        let translationThreshold = max(
            MobilePlayerGestureTuning.dismissMinimumTranslation,
            view.bounds.height * MobilePlayerGestureTuning.dismissTranslationHeightRatio
        )
        let shouldDismiss = projectedY > translationThreshold
            || (velocity.y > MobilePlayerGestureTuning.dismissFastSwipeVelocity
                && clampedY > MobilePlayerGestureTuning.dismissMinimumFastSwipeTranslation)

        if shouldDismiss {
            isDismissing = true
            view.isUserInteractionEnabled = false
            let remainingDistance = max(view.bounds.height - clampedY, 0)
            let velocityDuration = velocity.y > 0 ? remainingDistance / velocity.y : 0.24
            let duration = min(max(TimeInterval(velocityDuration), 0.14), 0.24)
            UIView.animate(withDuration: duration, delay: 0, options: [.curveEaseOut, .beginFromCurrentState], animations: {
                self.applyDismissPresentation(offsetY: self.view.bounds.height, progress: 1)
            }, completion: { _ in
                self.onDismiss()
            })
        } else {
            resetDismissTransform()
        }
    }

    private func applyDismissPresentation(offsetY: CGFloat, progress: CGFloat) {
        playerNavigationController.view.transform = CGAffineTransform(translationX: 0, y: offsetY)
        dimmingView.alpha = 1 - min(max(progress, 0), 1)
    }

    private func resetDismissTransform() {
        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0, options: [.beginFromCurrentState], animations: {
            self.playerNavigationController.view.transform = .identity
            self.dimmingView.alpha = 1
        })
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === controlsPan {
            let velocity = controlsPan.velocity(in: view)
            return velocity.y < -MobilePlayerGestureTuning.controlsRevealVelocity
                && abs(velocity.y) > abs(velocity.x) * MobilePlayerGestureTuning.controlsRevealVerticalIntentRatio
        }

        guard gestureRecognizer === dismissPan else {
            return true
        }
        guard !isDismissing else {
            return false
        }

        let location = dismissPan.location(in: playerNavigationController.view)
        let velocity = dismissPan.velocity(in: view)
        let bounds = playerNavigationController.view.bounds
        let isAwayFromHorizontalEdges = location.x > MobilePlayerGestureTuning.dismissHorizontalEdgeExclusion
            && location.x < bounds.width - MobilePlayerGestureTuning.dismissHorizontalEdgeExclusion

        if chrome.showControls {
            return bounds.contains(location)
                && velocity.y > 0
                && velocity.y > abs(velocity.x)
        }

        return playerNavigationController.view.bounds.contains(location)
            && isAwayFromHorizontalEdges
            && velocity.y > MobilePlayerGestureTuning.dismissInitialVelocity
            && velocity.y > abs(velocity.x) * MobilePlayerGestureTuning.dismissVerticalIntentRatio
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        gestureRecognizer === controlsPan || otherGestureRecognizer === controlsPan
    }

}

private extension UIView {

    func allSubviews<T: UIView>(ofType type: T.Type) -> [T] {
        subviews.flatMap { subview -> [T] in
            var matchingSubviews = subview.allSubviews(ofType: type)
            if let subview = subview as? T {
                matchingSubviews.append(subview)
            }
            return matchingSubviews
        }
    }

}
