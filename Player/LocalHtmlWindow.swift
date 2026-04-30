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
        
        let titleLabel = NSTextField(labelWithString: playerModel.currentToken.displayName)
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
        
        let nextCollectionButton = NSButton(image: Images.nextCollectionTitleBar, target: self, action: #selector(nextCollectionButtonClicked))
        nextCollectionButton.keyEquivalent = "\r"
        nextCollectionButton.isBordered = false
        nextCollectionButton.contentTintColor = .gray
        titleBarView.addSubview(nextCollectionButton)
        nextCollectionButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            nextCollectionButton.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            nextCollectionButton.trailingAnchor.constraint(equalTo: titleBarView.trailingAnchor, constant: -8)
        ])
        
        let listButton = NSButton(image: Images.playlistConfiguration, target: self, action: #selector(listButtonClicked))
        listButton.isBordered = false
        listButton.contentTintColor = .gray
        titleBarView.addSubview(listButton)
        listButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            listButton.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            listButton.trailingAnchor.constraint(equalTo: nextCollectionButton.leadingAnchor, constant: -8)
        ])
        
        let infoButton = NSButton(image: Images.infoTitleBar, target: self, action: #selector(infoButtonClicked))
        infoButton.isBordered = false
        infoButton.contentTintColor = .gray
        titleBarView.addSubview(infoButton)
        infoButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            infoButton.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            infoButton.trailingAnchor.constraint(equalTo: listButton.leadingAnchor, constant: -8)
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
                let constraint = titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: infoButton.leadingAnchor, constant: -8)
                constraint.priority = .defaultHigh
                return constraint
            }()
        ])
        
        navigationKeysEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 0x22 && event.modifierFlags.intersection(.deviceIndependentFlagsMask) == [] {
                self?.infoButtonClicked()
                return nil
            }
            
            switch event.charactersIgnoringModifiers?.unicodeScalars.first?.value {
            case 0x0D:
                if self?.playerModel.showingListPopover == false {
                    self?.nextCollectionButtonClicked()
                    return nil
                }
            case 0xF700, 0xF702:
                self?.backButtonClicked()
                return nil
            case 0xF701, 0xF703, 0x20:
                self?.forwardButtonClicked()
                return nil
            default:
                return event
            }
            
            return event
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
    
    @objc private func nextCollectionButtonClicked() {
        playerModel.changeCollection()
        updateTitle()
    }
    
    @objc private func listButtonClicked() {
        playerModel.showingListPopover.toggle()
    }
    
    @objc private func forwardButtonClicked() {
        playerModel.goForward()
        updateTitle()
    }
    
    @objc private func backButtonClicked() {
        playerModel.goBack()
        updateTitle()
    }
    
    @objc private func infoButtonClicked() {
        playerModel.showingInfoPopover.toggle()
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
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: playerModel.currentToken.displayName, action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: Strings.info, action: #selector(infoButtonClicked), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: Strings.back, action: #selector(backButtonClicked), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: Strings.forward, action: #selector(forwardButtonClicked), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: Strings.editPlaylist, action: #selector(listButtonClicked), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: Strings.nextCollection, action: #selector(nextCollectionButtonClicked), keyEquivalent: ""))
        if let event = NSApp.currentEvent {
            NSMenu.popUpContextMenu(menu, with: event, for: view)
        }
    }
    
    func updateTitle() {
        let newTitle = playerModel.currentToken.displayName
        titleLabel?.stringValue = newTitle
        title = newTitle
    }
    
}
