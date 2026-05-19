// ∅ 2026 lil org

import Cocoa
import Combine
import SwiftUI

class LocalHtmlWindow: NSWindow {
    
    private var playerModel: PlayerModel
    private let navigationBridge = MacPlayerNavigationBridge()
    private var cursorHideTimer: Timer?
    private var mouseMoveEventMonitor: Any?
    private var navigationKeysEventMonitor: Any?
    private var currentTokenObserver: AnyCancellable?
    private weak var titleLabel: NSTextField?
    private weak var bookmarkButton: NSButton?

    private var isFullScreenOnActiveSpace: Bool {
        return styleMask.contains(.fullScreen) && isOnActiveSpace
    }
    
    init(playerModel: PlayerModel, contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        self.playerModel = playerModel
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        
        let htmlView = LocalHtmlView(
            playerModel: playerModel,
            windowNumber: windowNumber,
            playerMenuDelegate: self,
            navigationBridge: navigationBridge,
            onViewAgain: { [weak self] in self?.viewAgainButtonClicked() },
            onFinish: { [weak self] in self?.finishButtonClicked() }
        )
        .background(.black)
        self.contentView = NSHostingView(rootView: htmlView.frame(minWidth: 251, minHeight: 130))
        
        if NSScreen.screens.count <= 1 {
            mouseMoveEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseUp, .rightMouseUp, .mouseEntered]) { [weak self] event in
                self?.resetCursorHideTimer()
                return event
            }
        }
        
        setupTitleBar()
        currentTokenObserver = playerModel.$currentToken
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] token in
                self?.updatePlayerChrome(for: token)
            }
        playerModel.markCurrentTokenViewed()
        Window.registerPlayerWindow(self)
    }

    override func close() {
        Window.unregisterPlayerWindow(self)
        super.close()
    }
    
    private func setupTitleBar() {
        guard let closeButton = standardWindowButton(.closeButton), let titleBarView = closeButton.superview else { return }
        
        titleBarView.wantsLayer = true
        titleBarView.layer?.backgroundColor = .black
        
        let titleLabel = NSTextField(labelWithString: playerModel.playerWindowTitle)
        titleLabel.font = NSFont.preferredFont(forTextStyle: .callout)
        titleLabel.textColor = .gray
        titleLabel.backgroundColor = .clear
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleLabel.isBezeled = false
        titleLabel.isEditable = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleBarView.addSubview(titleLabel)
        self.titleLabel = titleLabel
        updateTitle()
        
        let moreButton = NSButton(image: Images.moreTitleBar, target: self, action: #selector(moreButtonClicked(_:)))
        moreButton.isBordered = false
        moreButton.contentTintColor = .gray
        moreButton.imageScaling = .scaleProportionallyDown
        moreButton.toolTip = Strings.more
        moreButton.setAccessibilityLabel(Strings.more)
        titleBarView.addSubview(moreButton)
        moreButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            moreButton.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            moreButton.trailingAnchor.constraint(equalTo: titleBarView.trailingAnchor, constant: -8),
            moreButton.widthAnchor.constraint(equalToConstant: 28),
            moreButton.heightAnchor.constraint(equalToConstant: 24)
        ])

        let bookmarkButton = NSButton(image: Images.bookmarkTitleBar, target: self, action: #selector(bookmarkButtonClicked))
        bookmarkButton.isBordered = false
        bookmarkButton.contentTintColor = .gray
        bookmarkButton.imageScaling = .scaleProportionallyDown
        titleBarView.addSubview(bookmarkButton)
        bookmarkButton.translatesAutoresizingMaskIntoConstraints = false
        self.bookmarkButton = bookmarkButton
        updateBookmarkButton()
        NSLayoutConstraint.activate([
            bookmarkButton.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            bookmarkButton.trailingAnchor.constraint(equalTo: moreButton.leadingAnchor, constant: -4),
            bookmarkButton.widthAnchor.constraint(equalToConstant: 28),
            bookmarkButton.heightAnchor.constraint(equalToConstant: 24)
        ])
        
        let leftButton = NSButton(image: Images.backTitleBar, target: self, action: #selector(backButtonClicked))
        leftButton.isBordered = false
        leftButton.contentTintColor = .gray
        titleBarView.addSubview(leftButton)
        leftButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            leftButton.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            leftButton.leadingAnchor.constraint(equalTo: closeButton.trailingAnchor, constant: 54)
        ])
        
        let rightButton = NSButton(image: Images.forwardTitleBar, target: self, action: #selector(forwardButtonClicked))
        rightButton.isBordered = false
        rightButton.contentTintColor = .gray
        titleBarView.addSubview(rightButton)
        rightButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            rightButton.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            rightButton.leadingAnchor.constraint(equalTo: leftButton.trailingAnchor, constant: 8)
        ])
        
        NSLayoutConstraint.activate([
            titleLabel.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            {
                let constraint = titleLabel.centerXAnchor.constraint(equalTo: titleBarView.centerXAnchor)
                constraint.priority = .defaultLow
                return constraint
            }(),
            {
                let constraint = titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: rightButton.trailingAnchor, constant: 8)
                constraint.priority = .defaultHigh
                return constraint
            }(),
            {
                let constraint = titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: bookmarkButton.leadingAnchor, constant: -8)
                constraint.priority = .defaultHigh
                return constraint
            }()
        ])
        
        navigationKeysEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            guard self.shouldHandleNavigationKeyEvent(event) else {
                return event
            }
            guard let navigationAction = Self.navigationAction(for: event) else {
                return event
            }
            self.performNavigation(navigationAction)
            return nil
        }
    }
    
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) {
            return false
        } else {
            return super.performKeyEquivalent(with: event)
        }
    }
    
    private func resetCursorHideTimer() {
        cursorHideTimer?.invalidate()
        if isFullScreenOnActiveSpace {
            cursorHideTimer = Timer.scheduledTimer(withTimeInterval: 2.3, repeats: false) { [weak self] _ in
                if self?.isFullScreenOnActiveSpace == true {
                    NSCursor.setHiddenUntilMouseMoves(true)
                }
            }
        }
    }
    
    @objc private func moreButtonClicked(_ sender: NSButton) {
        popUpMoreMenu(from: sender)
    }

    @objc private func bookmarkButtonClicked() {
        guard canBookmark(playerModel.currentToken) else { return }

        PlayerBookmarksStore.toggleBookmark(
            collectionId: playerModel.currentToken.fullCollectionId,
            tokenId: playerModel.currentToken.id
        )
        updateBookmarkButton()
    }

    @objc private func viewAgainButtonClicked() {
        playerModel.restartCollection()
    }

    @objc private func finishButtonClicked() {
        close()
    }
    
    @objc private func forwardButtonClicked() {
        navigationBridge.goForward(animation: .immediate)
    }
    
    @objc private func backButtonClicked() {
        navigationBridge.goBack(animation: .immediate)
    }
    
    @objc private func viewOnWeb() {
        if let url = playerModel.currentToken.url {
            NSWorkspace.shared.open(url)
        }
    }

    private func makeMoreMenu() -> NSMenu {
        let menu = NSMenu()
        let viewOnWebItem = NSMenuItem(
            title: Strings.viewOnBlockExplorer,
            action: #selector(viewOnWeb),
            keyEquivalent: ""
        )
        viewOnWebItem.target = self
        menu.addItem(viewOnWebItem)
        return menu
    }

    private func popUpMoreMenu(from view: NSView) {
        makeMoreMenu().popUp(
            positioning: nil,
            at: NSPoint(x: 0, y: view.bounds.height),
            in: view
        )
    }

    private func updateTitle(for token: GeneratedToken? = nil) {
        let newTitle = token.map { playerModel.playerWindowTitle(for: $0) } ?? playerModel.playerWindowTitle
        titleLabel?.stringValue = newTitle
        title = newTitle
    }

    private func canBookmark(_ token: GeneratedToken) -> Bool {
        !token.fullCollectionId.isEmpty && !token.id.isEmpty
    }

    private func isTokenBookmarked(_ token: GeneratedToken) -> Bool {
        PlayerBookmarksStore.isBookmarked(
            collectionId: token.fullCollectionId,
            tokenId: token.id
        )
    }

    private func updateBookmarkButton(for token: GeneratedToken? = nil) {
        guard let bookmarkButton else { return }

        let token = token ?? playerModel.currentToken
        let canBookmark = canBookmark(token)
        bookmarkButton.isHidden = !canBookmark
        let isBookmarked = canBookmark && isTokenBookmarked(token)
        bookmarkButton.image = isBookmarked ? Images.bookmarkFillTitleBar : Images.bookmarkTitleBar
        let label = isBookmarked ? Strings.removeBookmark : Strings.bookmark
        bookmarkButton.toolTip = label
        bookmarkButton.setAccessibilityLabel(label)
    }

    private func updatePlayerChrome(for token: GeneratedToken? = nil) {
        let token = token ?? playerModel.currentToken
        playerModel.markTokenViewed(token)
        updateTitle(for: token)
        updateBookmarkButton(for: token)
    }

    private func performNavigation(_ action: PlayerNavigationKeyAction) {
        switch action {
        case .back(let animation):
            navigationBridge.goBack(animation: animation)
        case .forward(let animation):
            navigationBridge.goForward(animation: animation)
        }
    }

    private func shouldHandleNavigationKeyEvent(_ event: NSEvent) -> Bool {
        guard isKeyWindow, event.window === self else { return false }
        guard !(firstResponder is NSTextView) else { return false }
        return true
    }

    private static func navigationAction(for event: NSEvent) -> PlayerNavigationKeyAction? {
        let shortcutModifiers: NSEvent.ModifierFlags = [.command, .control, .option]
        guard event.modifierFlags.intersection(shortcutModifiers).isEmpty else { return nil }
        guard let characters = event.charactersIgnoringModifiers?.lowercased(),
              let scalar = characters.unicodeScalars.first else {
            return nil
        }

        switch scalar.value {
        case 0x20:
            return .forward(animation: .animated)
        case 0xF700, 0xF703:
            return .forward(animation: .immediate)
        case 0xF701, 0xF702:
            return .back(animation: .immediate)
        default:
            break
        }

        switch characters {
        case "w", "d":
            return .forward(animation: .immediate)
        case "a", "s":
            return .back(animation: .immediate)
        default:
            return nil
        }
    }
    
    deinit {
        if let monitor = mouseMoveEventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        
        if let monitor = navigationKeysEventMonitor {
            NSEvent.removeMonitor(monitor)
        }

        Window.unregisterPlayerWindow(self)
    }
    
}

private enum PlayerNavigationKeyAction {
    case back(animation: MacPlayerNavigationAnimation)
    case forward(animation: MacPlayerNavigationAnimation)
}

extension LocalHtmlWindow: PlayerMenuDelegate {
    
    func popUpMenu(view: NSView) {
        if let event = NSApp.currentEvent {
            NSMenu.popUpContextMenu(makeMoreMenu(), with: event, for: view)
        } else {
            popUpMoreMenu(from: view)
        }
    }

}
