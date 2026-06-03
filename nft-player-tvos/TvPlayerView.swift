// ∅ 2026 lil org

import SwiftUI
import UIKit

struct TvPlayerView: View {
    
    @StateObject private var playerModel: PlayerModel
    @State private var isChromeVisible = false
    @State private var preferredPrefetchDirection: DownloadableMediaCache.PrefetchDirection = .forward
    @State private var bookmarkHUDState: TvBookmarkHUDState?
    
    init(
        initialItemId: String?,
        initialTokenId: String? = nil,
        continueViewingCollectionId: String? = nil
    ) {
        _playerModel = StateObject(
            wrappedValue: TvPlayerPrewarmer.preparedModel(
                initialItemId: initialItemId,
                initialTokenId: initialTokenId,
                continueViewingCollectionId: continueViewingCollectionId
            )
        )
    }
    
    var body: some View {
        ZStack {
            mediaView(for: playerModel.currentToken)
                .edgesIgnoringSafeArea(.all)
                .onAppear {
                    playerModel.markCurrentTokenViewed()
                    playerModel.refreshCurrentTokenBookmarkState()
                }
                .onChange(of: playerModel.currentToken) { _ in
                    playerModel.markCurrentTokenViewed()
                }

            TvPlayerInputSurface(
                onBookmarkToggle: toggleCurrentTokenBookmark,
                onMove: handleMoveCommand,
                onPlayPause: toggleChromeVisibility,
                accessibilityLabel: playerModel.isCurrentTokenBookmarked ? Strings.removeBookmark : Strings.bookmark
            )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .edgesIgnoringSafeArea(.all)
            
            if isChromeVisible {
                chromeView()
                    .padding(48)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }

            if let bookmarkHUDState {
                TvBookmarkHUDView(state: bookmarkHUDState)
                    .id(bookmarkHUDState.id)
                    .transition(.scale(scale: 0.86).combined(with: .opacity))
            }
        }
        .navigationBarHidden(true)
    }

    private func mediaView(for token: GeneratedToken) -> some View {
        let context = CollectionCatalog.tokenContext(for: token)
        return TvPlayerMediaView(
            token: token,
            context: context,
            preferredPrefetchDirection: preferredPrefetchDirection
        )
        .id(TvPlayerMediaIdentity(token: token, context: context))
    }

    private func navigateBack() {
        DispatchQueue.main.async {
            preferredPrefetchDirection = .backward
            playerModel.goBack()
        }
    }

    private func navigateForward() {
        DispatchQueue.main.async {
            guard !isCurrentCollectionComplete else {
                showChrome()
                return
            }

            preferredPrefetchDirection = .forward
            playerModel.goForward()
        }
    }

    private func handleMoveCommand(_ direction: MoveCommandDirection) {
        switch direction {
        case .left, .down:
            navigateBack()
        case .right, .up:
            navigateForward()
        default:
            break
        }
    }

    private func toggleChromeVisibility() {
        withAnimation(.easeInOut(duration: 0.16)) {
            isChromeVisible.toggle()
        }
    }

    private func showChrome() {
        guard !isChromeVisible else { return }

        withAnimation(.easeInOut(duration: 0.16)) {
            isChromeVisible = true
        }
    }

    private func toggleCurrentTokenBookmark() {
        guard playerModel.canBookmarkCurrentToken else { return }

        let isBookmarked = playerModel.toggleCurrentTokenBookmark()
        guard !isChromeVisible else { return }

        let hudState = TvBookmarkHUDState(isBookmarked: isBookmarked)
        withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
            bookmarkHUDState = hudState
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.15) {
            guard bookmarkHUDState?.id == hudState.id else { return }
            withAnimation(.easeInOut(duration: 0.18)) {
                bookmarkHUDState = nil
            }
        }
    }

    private func chromeView() -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(uiImage: Images.generateQRCode(playerModel.currentToken.url?.absoluteString ?? ""))
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(width: 200, height: 200)

            VStack(alignment: .leading, spacing: 8) {
                Text(chromeCollectionName)
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)

                if let pageLabel = playerModel.currentProgress?.pageLabel,
                   !pageLabel.isEmpty {
                    Text(pageLabel)
                        .font(.headline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                if playerModel.canBookmarkCurrentToken {
                    Label(
                        playerModel.isCurrentTokenBookmarked ? Strings.removeBookmark : Strings.bookmark,
                        systemImage: playerModel.isCurrentTokenBookmarked
                            ? Images.bookmarkFillSystemName
                            : Images.bookmarkSystemName
                    )
                    .font(.headline.weight(.semibold))
                }
            }
        }
        .foregroundStyle(.white)
        .padding(22)
        .frame(width: 292, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var chromeCollectionName: String {
        let collectionName = playerModel.currentToken.collectionName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !collectionName.isEmpty {
            return collectionName
        }
        return Strings.nftPlayer
    }

    private var isCurrentCollectionComplete: Bool {
        playerModel.currentProgress?.isComplete == true && !playerModel.isCurrentTokenInsertedWidgetToken
    }
    
}

private struct TvPlayerMediaIdentity: Hashable {
    let collectionId: String
    let tokenId: String?
    let media: GeneratedTokenMedia?

    init(token: GeneratedToken, context: PlayerTokenContext?) {
        self.collectionId = context?.collectionId ?? token.fullCollectionId
        self.media = token.media
        // Reuse the legacy tvOS web view while paging generated HTML within one collection.
        self.tokenId = token.media == nil ? nil : token.id
    }
}

private struct TvBookmarkHUDState: Identifiable {
    let id = UUID()
    let isBookmarked: Bool
}

private struct TvBookmarkHUDView: View {
    let state: TvBookmarkHUDState

    var body: some View {
        VStack(spacing: 18) {
            (state.isBookmarked ? Images.bookmarkFill : Images.bookmark)
                .font(.system(size: 86, weight: .semibold))
                .symbolRenderingMode(.hierarchical)

            Text(state.isBookmarked ? Strings.bookmarked : Strings.bookmarkRemoved)
                .font(.title2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 48)
        .padding(.vertical, 36)
        .background(Color.black.opacity(0.68), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

private struct TvPlayerInputSurface: UIViewControllerRepresentable {
    let onBookmarkToggle: () -> Void
    let onMove: (MoveCommandDirection) -> Void
    let onPlayPause: () -> Void
    let accessibilityLabel: String

    func makeUIViewController(context: Context) -> TvPlayerInputViewController {
        let viewController = TvPlayerInputViewController()
        update(viewController)
        return viewController
    }

    func updateUIViewController(_ uiViewController: TvPlayerInputViewController, context: Context) {
        update(uiViewController)
    }

    private func update(_ viewController: TvPlayerInputViewController) {
        viewController.onSelect = onBookmarkToggle
        viewController.onMove = onMove
        viewController.onPlayPause = onPlayPause
        viewController.accessibilityLabel = accessibilityLabel
    }
}

private final class TvPlayerInputViewController: UIViewController {
    private let focusView = TvPlayerInputView()

    var onSelect: (() -> Void)? {
        get { focusView.onSelect }
        set { focusView.onSelect = newValue }
    }

    var onMove: ((MoveCommandDirection) -> Void)? {
        get { focusView.onMove }
        set { focusView.onMove = newValue }
    }

    var onPlayPause: (() -> Void)? {
        get { focusView.onPlayPause }
        set { focusView.onPlayPause = newValue }
    }

    override var accessibilityLabel: String? {
        get { focusView.accessibilityLabel }
        set { focusView.accessibilityLabel = newValue }
    }

    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        [focusView]
    }

    override func loadView() {
        view = focusView
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        requestFocus()
    }

    func requestFocus() {
        setNeedsFocusUpdate()
        updateFocusIfNeeded()
    }
}

private final class TvPlayerInputView: UIView {
    var onSelect: (() -> Void)?
    var onMove: ((MoveCommandDirection) -> Void)?
    var onPlayPause: (() -> Void)?

    override var canBecomeFocused: Bool {
        true
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isAccessibilityElement = true
        accessibilityTraits = .button
        installSwipeGestures()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let unhandledPresses = unhandledPresses(from: presses)
        if !unhandledPresses.isEmpty {
            super.pressesBegan(unhandledPresses, with: event)
        }
    }

    override func pressesChanged(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let unhandledPresses = unhandledPresses(from: presses)
        if !unhandledPresses.isEmpty {
            super.pressesChanged(unhandledPresses, with: event)
        }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if let press = presses.first(where: isHandledPress) {
            performAction(for: press)
        }

        let unhandledPresses = unhandledPresses(from: presses)
        if !unhandledPresses.isEmpty {
            super.pressesEnded(unhandledPresses, with: event)
        }
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let unhandledPresses = unhandledPresses(from: presses)
        if !unhandledPresses.isEmpty {
            super.pressesCancelled(unhandledPresses, with: event)
        }
    }

    override func accessibilityActivate() -> Bool {
        onSelect?()
        return true
    }

    private func installSwipeGestures() {
        [
            UISwipeGestureRecognizer.Direction.left,
            .right,
            .up,
            .down
        ].forEach { direction in
            let recognizer = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipe(_:)))
            recognizer.direction = direction
            addGestureRecognizer(recognizer)
        }
    }

    @objc private func handleSwipe(_ recognizer: UISwipeGestureRecognizer) {
        guard recognizer.state == .ended else { return }

        switch recognizer.direction {
        case .left:
            onMove?(.left)
        case .right:
            onMove?(.right)
        case .up:
            onMove?(.up)
        case .down:
            onMove?(.down)
        default:
            break
        }
    }

    private func unhandledPresses(from presses: Set<UIPress>) -> Set<UIPress> {
        presses.filter { !isHandledPress($0) }
    }

    private func isHandledPress(_ press: UIPress) -> Bool {
        switch press.type {
        case .select, .playPause, .leftArrow, .rightArrow, .upArrow, .downArrow:
            return true
        default:
            return false
        }
    }

    private func performAction(for press: UIPress) {
        switch press.type {
        case .select:
            onSelect?()
        case .playPause:
            onPlayPause?()
        case .leftArrow:
            onMove?(.left)
        case .rightArrow:
            onMove?(.right)
        case .upArrow:
            onMove?(.up)
        case .downArrow:
            onMove?(.down)
        default:
            break
        }
    }
}
