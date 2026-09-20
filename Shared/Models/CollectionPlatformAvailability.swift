nonisolated enum CollectionPlatformAvailability {
    enum Platform: CaseIterable, Sendable {
        case iOS
        case macOS
        case visionOS
        case tvOS
        case watchOS

        static var current: Self {
#if os(iOS)
            .iOS
#elseif os(visionOS)
            .visionOS
#elseif os(tvOS)
            .tvOS
#elseif os(watchOS)
            .watchOS
#else
            .macOS
#endif
        }
    }

    static func isAvailable(
        iosOnly: Bool?,
        generativeOnly: Bool?,
        on platform: Platform = .current
    ) -> Bool {
        platform == .iOS || iosOnly != true || generativeOnly != true
    }

    static func isRendererAvailable(
        collectionId: String,
        isNative: Bool,
        on platform: Platform = .current
    ) -> Bool {
        if isNative, platform == .visionOS || platform == .tvOS || platform == .watchOS {
            return false
        }

        switch collectionId {
        case "0x99a9b7c1116f9ceeb1652de04d5969cce509b069472",
             "0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270356",
             "0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270250":
            return platform != .visionOS && platform != .tvOS
        case "0x0a1bbd57033f57e7b6743621b79fcb9eb2ce367650",
             "0x0a1bbd57033f57e7b6743621b79fcb9eb2ce367667":
            return platform != .visionOS
        default:
            return true
        }
    }
}
