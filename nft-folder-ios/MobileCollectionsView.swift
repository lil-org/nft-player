import SwiftUI
import Combine
import UIKit

private enum MobileInitialPlayerCreationDelay {
    private static var shouldDeferNextPlayerCreation = true
    
    static func consumeShouldDefer() -> Bool {
        guard shouldDeferNextPlayerCreation else { return false }
        shouldDeferNextPlayerCreation = false
        return true
    }
}

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
    @State private var showSettingsPopup = false
    @State private var suggestedItems = TokenGenerator.allGenerativeSuggestedItems
    @State private var didAppear = false
    @State private var showMorePreferences = false
    @State private var playerConfig: MobilePlayerConfig?
    
    init() {
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
                VStack {
                    InfiniteCollectionsGridView(items: suggestedItems, onSelect: didSelectSuggestedItem)
                        .ignoresSafeArea()
                }
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
                        HStack {
                            Button { showRandomPlayer() } label: {
                                Images.shuffle
                            }
                        }
                        
                    }
                }
            }

            if let playerConfig {
                PlayerNavigationOverlay(config: playerConfig) {
                    dismissPlayer(playerConfig)
                }
                .ignoresSafeArea()
                .persistentSystemOverlays(.hidden)
                .zIndex(1)
                .id(playerConfig.id)
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
    
    private func didSelectSuggestedItem(_ item: SuggestedItem) {
        playerConfig = MobilePlayerConfig(initialItemId: item.id)
        Haptic.selectionChanged()
    }
    
    private func showRandomPlayer() {
        playerConfig = MobilePlayerConfig(initialItemId: nil)
        Haptic.selectionChanged()
    }

    private func dismissPlayer(_ config: MobilePlayerConfig) {
        guard playerConfig?.id == config.id else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            playerConfig = nil
        }
    }
    
}

private struct InfiniteCollectionsGridView: UIViewRepresentable {
    let items: [SuggestedItem]
    let onSelect: (SuggestedItem) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(items: [], onSelect: onSelect)
    }

    func makeUIView(context: Context) -> InfiniteCollectionsGridContainerView {
        let containerView = InfiniteCollectionsGridContainerView()
        containerView.update(items: items, coordinator: context.coordinator)
        return containerView
    }

    func updateUIView(_ containerView: InfiniteCollectionsGridContainerView, context: Context) {
        context.coordinator.onSelect = onSelect
        containerView.update(items: items, coordinator: context.coordinator)
    }

    final class Coordinator: NSObject, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
        var items: [SuggestedItem]
        var onSelect: (SuggestedItem) -> Void
        private var isRecentering = false

        init(items: [SuggestedItem], onSelect: @escaping (SuggestedItem) -> Void) {
            self.items = items
            self.onSelect = onSelect
        }

        func update(items: [SuggestedItem]) -> Bool {
            guard self.items != items else { return false }
            self.items = items
            return true
        }

        func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
            InfiniteCollectionsLoop.virtualItemCount(itemCount: items.count)
        }

        func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: CollectionGridCell.reuseIdentifier, for: indexPath)
            guard let gridCell = cell as? CollectionGridCell else { return cell }
            gridCell.configure(item: item(for: indexPath.item))
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

    func update(items: [SuggestedItem], coordinator: InfiniteCollectionsGridView.Coordinator) {
        self.coordinator = coordinator
        collectionView.dataSource = coordinator
        collectionView.delegate = coordinator

        if coordinator.update(items: items) {
            didSetInitialScrollPosition = false
            collectionView.reloadData()
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
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageView.image = nil
        titleLabel.text = nil
    }

    func configure(item: SuggestedItem) {
        imageView.image = UIImage(named: item.id)
        titleLabel.text = item.name
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

private struct PlayerNavigationOverlay: UIViewControllerRepresentable {
    
    let config: MobilePlayerConfig
    let onDismiss: () -> Void
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onDismiss: onDismiss)
    }
    
    func makeUIViewController(context: Context) -> PlayerOverlayViewController {
        let rootViewController = UIViewController()
        rootViewController.view.backgroundColor = .clear
        rootViewController.view.isOpaque = false
        rootViewController.navigationItem.backButtonTitle = Strings.nftFolder
        rootViewController.navigationItem.backButtonDisplayMode = .minimal
        
        let shouldDeferPlayerCreation = MobileInitialPlayerCreationDelay.consumeShouldDefer()
        let deferredPlayerViewController = shouldDeferPlayerCreation ? DeferredMobilePlayerViewController(config: config) : nil
        let playerViewController: UIViewController = deferredPlayerViewController ?? makeMobilePlayerViewController(config: config)
        
        let navigationController = PlayerNavigationController(rootViewController: rootViewController)
        navigationController.view.backgroundColor = .clear
        navigationController.view.isOpaque = false
        navigationController.navigationBar.isTranslucent = true
        navigationController.delegate = context.coordinator
        navigationController.setNavigationBarHidden(false, animated: false)
        
        let overlayViewController = PlayerOverlayViewController(
            navigationController: navigationController,
            onDismiss: onDismiss
        )
        
        context.coordinator.rootViewController = rootViewController
        context.coordinator.playerViewController = playerViewController
        context.coordinator.deferredPlayerViewController = deferredPlayerViewController
        context.coordinator.overlayViewController = overlayViewController
        
        DispatchQueue.main.async {
            guard navigationController.viewControllers.last === rootViewController else { return }
            navigationController.pushViewController(playerViewController, animated: true)
            navigationController.setNeedsStatusBarAppearanceUpdate()
        }
        
        return overlayViewController
    }
    
    func updateUIViewController(_ overlayViewController: PlayerOverlayViewController, context: Context) {
        context.coordinator.onDismiss = onDismiss
        overlayViewController.onDismiss = onDismiss
    }
    
    final class Coordinator: NSObject, UINavigationControllerDelegate {
        
        var onDismiss: () -> Void
        weak var rootViewController: UIViewController?
        weak var overlayViewController: PlayerOverlayViewController?
        var playerViewController: UIViewController?
        var deferredPlayerViewController: DeferredMobilePlayerViewController?
        private var didShowPlayer = false
        private var didNotifyDismiss = false
        
        init(onDismiss: @escaping () -> Void) {
            self.onDismiss = onDismiss
        }
        
        func navigationController(_ navigationController: UINavigationController, didShow viewController: UIViewController, animated: Bool) {
            if viewController === playerViewController {
                didShowPlayer = true
                installDeferredPlayerIfNeeded(in: navigationController)
                overlayViewController?.didUpdateNavigationStack()
                return
            }
            
            guard didShowPlayer,
                  viewController === rootViewController,
                  !didNotifyDismiss else {
                return
            }
            
            didNotifyDismiss = true
            onDismiss()
        }
        
        private func installDeferredPlayerIfNeeded(in navigationController: UINavigationController) {
            guard let deferredPlayerViewController else { return }
            
            let playerViewController = makeMobilePlayerViewController(config: deferredPlayerViewController.config)
            var viewControllers = navigationController.viewControllers
            guard let index = viewControllers.firstIndex(of: deferredPlayerViewController) else { return }
            viewControllers[index] = playerViewController
            self.playerViewController = playerViewController
            self.deferredPlayerViewController = nil
            navigationController.setViewControllers(viewControllers, animated: false)
        }
        
    }
    
}

private func makeMobilePlayerViewController(config: MobilePlayerConfig) -> UIHostingController<MobilePlayerView> {
    let playerViewController = UIHostingController(rootView: MobilePlayerView(config: config))
    playerViewController.view.backgroundColor = .clear
    playerViewController.view.isOpaque = false
    return playerViewController
}

private final class DeferredMobilePlayerViewController: UIViewController {
    
    let config: MobilePlayerConfig
    
    init(config: MobilePlayerConfig) {
        self.config = config
        super.init(nibName: nil, bundle: nil)
        navigationItem.hidesBackButton = true
    }
    
    required init?(coder: NSCoder) {
        fatalError("yo")
    }
    
    override var prefersStatusBarHidden: Bool {
        true
    }
    
    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation {
        .fade
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: false)
    }
    
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
    var onDismiss: () -> Void

    private lazy var topDismissPan = UIPanGestureRecognizer(target: self, action: #selector(handleTopDismissPan(_:)))
    private var configuredScrollPanGestures = Set<ObjectIdentifier>()
    private var isTopDismissing = false

    init(navigationController: UINavigationController, onDismiss: @escaping () -> Void) {
        self.playerNavigationController = navigationController
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

        topDismissPan.delegate = self
        topDismissPan.cancelsTouchesInView = false
        view.addGestureRecognizer(topDismissPan)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        configurePagingScrollViews()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        configurePagingScrollViews()
    }

    func didUpdateNavigationStack() {
        configurePagingScrollViews()
        setNeedsStatusBarAppearanceUpdate()
    }

    private func configurePagingScrollViews() {
        playerNavigationController.view
            .allSubviews(ofType: UIScrollView.self)
            .forEach { scrollView in
                let panGestureId = ObjectIdentifier(scrollView.panGestureRecognizer)
                if !configuredScrollPanGestures.contains(panGestureId) {
                    scrollView.panGestureRecognizer.require(toFail: topDismissPan)
                    configuredScrollPanGestures.insert(panGestureId)
                }
                scrollView.hideAutomaticScrollEdgeEffects()
            }
    }

    @objc private func handleTopDismissPan(_ gesture: UIPanGestureRecognizer) {
        guard !isTopDismissing else { return }

        let translation = gesture.translation(in: view)
        let clampedY = max(0, translation.y)

        switch gesture.state {
        case .began:
            playerNavigationController.view.layer.removeAllAnimations()

        case .changed:
            let progress = min(clampedY / 700, 1)
            applyTransform(
                scale: 1 - progress * 0.14,
                offsetX: translation.x * 0.22,
                offsetY: clampedY
            )

        case .ended:
            finishTopDismissGesture(translation: translation, velocity: gesture.velocity(in: view))

        case .cancelled, .failed:
            resetTopDismissTransform()

        default:
            break
        }
    }

    private func finishTopDismissGesture(translation: CGPoint, velocity: CGPoint) {
        let clampedY = max(0, translation.y)
        let shouldDismiss = clampedY > 120 || (velocity.y > 500 && clampedY > 20)

        if shouldDismiss {
            isTopDismissing = true
            UIView.animate(withDuration: 0.18, delay: 0, options: [.curveEaseOut, .beginFromCurrentState], animations: {
                self.applyTransform(scale: 0.82, offsetX: 0, offsetY: self.view.bounds.height)
            }, completion: { _ in
                self.onDismiss()
            })
        } else {
            resetTopDismissTransform()
        }
    }

    private func applyTransform(scale: CGFloat, offsetX: CGFloat, offsetY: CGFloat) {
        let anchorCompensation = playerNavigationController.view.bounds.height * (1 - scale) / 2
        let scaleTransform = CGAffineTransform(scaleX: scale, y: scale)
        let translateTransform = CGAffineTransform(translationX: offsetX, y: offsetY - anchorCompensation)
        playerNavigationController.view.transform = scaleTransform.concatenating(translateTransform)
    }

    private func resetTopDismissTransform() {
        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0, options: [.beginFromCurrentState], animations: {
            self.playerNavigationController.view.transform = .identity
        })
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === topDismissPan else {
            return true
        }
        guard playerNavigationController.viewControllers.count > 1, !isTopDismissing else {
            return false
        }

        let location = topDismissPan.location(in: view)
        let velocity = topDismissPan.velocity(in: view)
        let activationHeight = MobilePlayerGestureTuning.topDismissActivationHeight(safeAreaTop: view.safeAreaInsets.top)
        return location.y <= activationHeight
            && velocity.y > 0
            && velocity.y > abs(velocity.x) * MobilePlayerGestureTuning.topDismissVerticalIntentRatio
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
