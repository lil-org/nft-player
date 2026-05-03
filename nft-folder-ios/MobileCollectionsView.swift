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
                    ScrollView {
                        createGrid().frame(maxWidth: .infinity)
                    }
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
    
    private func createGrid() -> some View {
        let gridLayout = [GridItem(.adaptive(minimum: UIDevice.current.userInterfaceIdiom == .pad ? 130 : 77), spacing: 0)]
        return LazyVGrid(columns: gridLayout, alignment: .leading, spacing: 0) {
            ForEach(suggestedItems) { item in
                Button {
                    didSelectSuggestedItem(item)
                } label: {
                    ZStack {
                        Image(item.id)
                            .resizable()
                            .scaledToFill()
                            .clipped()
                            .aspectRatio(1, contentMode: .fill)
                            .contentShape(Rectangle())
                        VStack {
                            Spacer()
                            gridItemText(item.name) {
                                didSelectSuggestedItem(item)
                            }
                        }
                    }
                }
                .aspectRatio(1, contentMode: .fit)
                .contextMenu { suggestedItemContextMenu(item: item) }
            }
        }
    }
    
    private func gridItemText(_ text: String, onTap: @escaping () -> Void) -> some View {
        HStack {
            Text(text)
                .font(.system(size: 9, weight: .regular))
                .lineLimit(2)
                .foregroundColor(.white)
                .padding(.horizontal, 1)
                .background(Color.black.opacity(0.7))
                .cornerRadius(3)
                .padding(.leading, 4)
                .padding(.bottom, 3)
                .multilineTextAlignment(.leading)
                .onTapGesture { onTap() }
            Spacer()
        }
    }
    private func suggestedItemContextMenu(item: SuggestedItem) -> some View {
        Group {
            Text(item.name)
            Button(action: {
                didSelectSuggestedItem(item)
            }) {
                HStack {
                    Images.play
                    Text(Strings.play)
                }
            }
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
        let activationHeight = max(132, view.safeAreaInsets.top + 96)
        return location.y <= activationHeight
            && velocity.y > 0
            && velocity.y > abs(velocity.x) * 0.8
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
