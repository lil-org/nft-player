// ∅ 2026 lil org

import WebKit

class WebViewWithMenu: WKWebView {
    
    private weak var playerMenuDelegate: PlayerMenuDelegate?
    
    init(frame: CGRect, configuration: WKWebViewConfiguration, playerMenuDelegate: PlayerMenuDelegate?) {
        super.init(frame: frame, configuration: configuration)
        self.playerMenuDelegate = playerMenuDelegate
        setupRightClickGesture()
    }

    func updatePlayerMenuDelegate(_ playerMenuDelegate: PlayerMenuDelegate?) {
        self.playerMenuDelegate = playerMenuDelegate
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupRightClickGesture()
    }
    
    private func setupRightClickGesture() {
        let rightClickGestureRecognizer = NSClickGestureRecognizer(target: self, action: #selector(handleRightClick(_:)))
        rightClickGestureRecognizer.buttonMask = 0x2
        addGestureRecognizer(rightClickGestureRecognizer)
    }
    
    @objc private func handleRightClick(_ gestureRecognizer: NSClickGestureRecognizer) {
        playerMenuDelegate?.popUpMenu(view: self)
    }
    
}
