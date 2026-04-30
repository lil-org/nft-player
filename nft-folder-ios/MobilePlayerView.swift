// ∅ 2026 lil org

import SwiftUI
import UIKit

struct MobilePlayerConfig: Hashable, Codable, Identifiable {
    var id = UUID()
    var initialItemId: String?
    var specificToken: GeneratedToken?
}

private let doNotShowInstructionsTmp = true

struct MobilePlayerView: View {
    
    private let initialConfig: MobilePlayerConfig
    private let dismiss: () -> Void
    private let buttonShapesEnabled = UIAccessibility.buttonShapesEnabled
    
    @State private var showControls = false
    @State private var isAllowedToHideStatusBar = false
    @State private var currentToken = GeneratedToken.empty
    @State private var currentCoordinate = PlayerCoordinate(x: 0, y: 0)
    
    init(config: MobilePlayerConfig, dismiss: @escaping () -> Void) {
        self.initialConfig = config
        self.dismiss = dismiss
    }
    
    private func makeCircularImageView(image: Image) -> some View {
        image
            .frame(width: 23, height: 23)
            .padding(10)
            .background(.regularMaterial)
            .clipShape(Circle())
    }
    
    var body: some View {
        ZStack {
            FourDirectionalPlayerContainerView(initialConfig: initialConfig, onCoordinateUpdate: { newCoordinate in
                DispatchQueue.main.async {
                    self.currentCoordinate = newCoordinate
                    self.currentToken = MobilePlaybackController.shared.getToken(uuid: initialConfig.id, coordinate: newCoordinate)
                    updateExternalDisplayToken(currentToken)
                }
            }).edgesIgnoringSafeArea(.all)
                .onTapGesture {
                    showControls.toggle()
                }
                .onLongPressGesture {
                    showControls.toggle()
                }
                .statusBar(hidden: isAllowedToHideStatusBar && !showControls)
            
            if showControls {
                VStack {
                    HStack {
                        Button(action: {
                            dismiss()
                        }) {
                            makeCircularImageView(image: Images.close)
                        }
                        .padding()
                        Spacer()
                        Menu {
                            if !doNotShowInstructionsTmp, let instructions = currentToken.instructions {
                                Text(instructions)
                            }
                            Button(Strings.viewOnBlockscout, action: viewOnWeb)
                            Text(currentToken.displayName)
                        } label: {
                            makeCircularImageView(image: Images.info)
                        }
                        .padding()
                    }
                    Spacer()
                }
                
                VStack {
                    Spacer()
                    HStack(spacing: buttonShapesEnabled ? nil : 20) {
                        Button(action: {
                            goBack()
                        }) {
                            makeCircularImageView(image: Images.back)
                        }
                        .keyboardShortcut(.leftArrow, modifiers: [])
                        Button(action: {
                            goForward()
                        }) {
                            makeCircularImageView(image: Images.forward)
                        }
                        .keyboardShortcut(.rightArrow, modifiers: [])
                        Button(action: {
                            changeCollection()
                        }) {
                            makeCircularImageView(image: Images.changeCollection)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 30)
                }
            }
        }
        .onDisappear {
            updateExternalDisplayToken(GeneratedToken.empty)
        }
        .onAppear {
            if !isAllowedToHideStatusBar {
                let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene
                let window = scene?.windows.first
                let topSafeArea = window?.safeAreaInsets.top ?? 0
                if topSafeArea < 44 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(200)) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isAllowedToHideStatusBar = true
                        }
                    }
                } else {
                    isAllowedToHideStatusBar = true
                }
            }
        }
    }
    
    private func goForward() {
        MobilePlaybackController.shared.goForward(uuid: initialConfig.id)
    }
    
    private func goBack() {
        MobilePlaybackController.shared.goBack(uuid: initialConfig.id)
    }

    private func changeCollection() {
        MobilePlaybackController.shared.changeCollection(uuid: initialConfig.id)
    }
    
    private func viewOnWeb() {
        if let url = currentToken.url {
            UIApplication.shared.open(url)
        }
    }
    
}

// MARK: - Interactive Dismiss Container

struct InteractiveDismissContainer<Content: View>: UIViewControllerRepresentable {

    let content: Content
    let onDismiss: () -> Void

    init(onDismiss: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.onDismiss = onDismiss
    }

    func makeUIViewController(context: Context) -> InteractiveDismissViewController<Content> {
        InteractiveDismissViewController(content: content, onDismiss: onDismiss)
    }

    func updateUIViewController(_ controller: InteractiveDismissViewController<Content>, context: Context) {
        controller.updateContent(content)
    }
}

class InteractiveDismissViewController<Content: View>: UIViewController, UIGestureRecognizerDelegate {

    private var hostingController: UIHostingController<Content>
    private let onDismiss: () -> Void
    private var isDismissing = false
    private var dimmingView: UIView!

    init(content: Content, onDismiss: @escaping () -> Void) {
        self.hostingController = UIHostingController(rootView: content)
        self.onDismiss = onDismiss
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var childForStatusBarHidden: UIViewController? { hostingController }
    override var childForStatusBarStyle: UIViewController? { hostingController }

    func updateContent(_ content: Content) {
        guard !isDismissing else { return }
        hostingController.rootView = content
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        dimmingView = UIView()
        dimmingView.backgroundColor = .black
        view.addSubview(dimmingView)

        hostingController.view.backgroundColor = .clear
        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.didMove(toParent: self)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.delegate = self
        view.addGestureRecognizer(pan)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        dimmingView.frame = view.bounds
        if !isDismissing, hostingController.view.transform == .identity {
            hostingController.view.frame = view.bounds
        }
    }

    private func applyTransform(scale: CGFloat, offsetX: CGFloat, offsetY: CGFloat) {
        let anchorCompensation = hostingController.view.bounds.height * (1 - scale) / 2
        let scaleT = CGAffineTransform(scaleX: scale, y: scale)
        let translateT = CGAffineTransform(translationX: offsetX, y: offsetY - anchorCompensation)
        hostingController.view.transform = scaleT.concatenating(translateT)
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard !isDismissing else { return }
        let translation = gesture.translation(in: view)

        switch gesture.state {
        case .changed:
            let clampedY = max(0, translation.y)
            let progress = min(clampedY / 700, 1)
            applyTransform(scale: 1 - progress * 0.14,
                           offsetX: translation.x * 0.22,
                           offsetY: clampedY)
            dimmingView.alpha = CGFloat(1 - progress * 0.35)

        case .ended, .cancelled:
            let clampedY = max(0, translation.y)
            let velocity = gesture.velocity(in: view)

            if clampedY > 120 || (velocity.y > 500 && clampedY > 20) {
                isDismissing = true
                UIView.animate(withDuration: 0.18, delay: 0, options: .curveEaseOut, animations: {
                    self.applyTransform(scale: 0.82, offsetX: 0, offsetY: self.view.bounds.height)
                    self.dimmingView.alpha = 0
                }, completion: { _ in
                    self.onDismiss()
                })
            } else {
                UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0, options: [], animations: {
                    self.hostingController.view.transform = .identity
                    self.dimmingView.alpha = 1
                })
            }

        default:
            break
        }
    }

    // MARK: - UIGestureRecognizerDelegate

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
        let velocity = pan.velocity(in: view)
        return velocity.y > 0 && velocity.y > abs(velocity.x) * 0.8
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        if otherGestureRecognizer is UIPanGestureRecognizer, otherGestureRecognizer.view is UIScrollView {
            return true
        }
        return false
    }
}
