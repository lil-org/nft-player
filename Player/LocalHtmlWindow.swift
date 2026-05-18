// ∅ 2026 lil org

import Cocoa
import SwiftUI

class LocalHtmlWindow: NSWindow {
    
    private var playerModel: PlayerModel
    private var cursorHideTimer: Timer?
    private var mouseMoveEventMonitor: Any?
    private var navigationKeysEventMonitor: Any?
    private weak var titleLabel: NSTextField?

    private var isFullScreenOnActiveSpace: Bool {
        return styleMask.contains(.fullScreen) && isOnActiveSpace
    }
    
    init(playerModel: PlayerModel, contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        self.playerModel = playerModel
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        
        let htmlView = LocalHtmlView(playerModel: playerModel, windowNumber: windowNumber, playerMenuDelegate: self).background(.black)
        self.contentView = NSHostingView(rootView: htmlView.frame(minWidth: 251, minHeight: 130))
        
        if NSScreen.screens.count <= 1 {
            mouseMoveEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseUp, .rightMouseUp, .mouseEntered]) { [weak self] event in
                self?.resetCursorHideTimer()
                return event
            }
        }
        
        setupTitleBar()
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
                let constraint = titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: moreButton.leadingAnchor, constant: -8)
                constraint.priority = .defaultHigh
                return constraint
            }()
        ])
        
        navigationKeysEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            switch event.charactersIgnoringModifiers?.unicodeScalars.first?.value {
            case 0xF700, 0xF702:
                self?.backButtonClicked()
                return nil
            case 0xF701, 0xF703, 0x20:
                self?.forwardButtonClicked()
                return nil
            default:
                return event
            }
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
    
    @objc private func forwardButtonClicked() {
        playerModel.goForward()
        updateTitle()
    }
    
    @objc private func backButtonClicked() {
        playerModel.goBack()
        updateTitle()
    }
    
    @objc private func viewOnWeb() {
        if let url = playerModel.currentToken.url {
            NSWorkspace.shared.open(url)
        }
    }

    private func makeMoreMenu() -> NSMenu {
        let menu = NSMenu()
        let viewOnWebItem = NSMenuItem(
            title: Strings.viewOnWebTitle(for: playerModel.currentToken.url),
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

    private func updateTitle() {
        let newTitle = playerModel.playerWindowTitle
        titleLabel?.stringValue = newTitle
        title = newTitle
    }
    
    deinit {
        if let monitor = mouseMoveEventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        
        if let monitor = navigationKeysEventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
    
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
