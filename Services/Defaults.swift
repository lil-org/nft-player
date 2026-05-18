// ∅ 2026 lil org

import Foundation

struct Defaults {
    
    private static let userDefaults = UserDefaults.standard

    static var didShowTvPlayerTutorial: Bool {
        get {
            userDefaults.bool(forKey: "didShowTvPlayerTutorial")
        }
        set {
            userDefaults.set(newValue, forKey: "didShowTvPlayerTutorial")
        }
    }
    
    static var preferresInfoPopoverHidden: Bool {
        get {
            userDefaults.bool(forKey: "preferresInfoPopoverHidden")
        }
        set {
            userDefaults.set(newValue, forKey: "preferresInfoPopoverHidden")
        }
    }
    
}
