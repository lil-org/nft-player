// ∅ 2026 lil org

import Cocoa

/// The macOS twin of iOS's `MobilePlayerBackgroundColor`. A few collections declare a
/// player background in the catalogue (white, for artwork designed against it);
/// everything else letterboxes on black.
enum MacPlayerBackgroundColor {

    static let defaultColor = NSColor.black

    private static var cachedColorsByCollectionId = [String: NSColor]()

    static func color(forCollectionId collectionId: String?) -> NSColor {
        guard let collectionId, !collectionId.isEmpty else { return defaultColor }
        if let cached = cachedColorsByCollectionId[collectionId] {
            return cached
        }

        let color = CollectionCatalog.playerBackgroundColor(specificCollectionId: collectionId)
            .flatMap(NSColor.init(playerBackgroundColorString:))
            ?? defaultColor
        cachedColorsByCollectionId[collectionId] = color
        return color
    }

}

private extension NSColor {

    convenience init?(playerBackgroundColorString string: String) {
        guard let components = PlayerBackgroundColorComponents(string: string) else { return nil }
        self.init(
            srgbRed: components.red,
            green: components.green,
            blue: components.blue,
            alpha: 1
        )
    }

}
