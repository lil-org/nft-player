import XCTest
@testable import NftPlayerSyncCore

final class CollectionPlatformAvailabilityTests: XCTestCase {
    func testIOSOnlyRequiresBothFlagsOutsideIOS() {
        let cases: [(Bool?, Bool?, Bool)] = [
            (nil, nil, true),
            (nil, false, true),
            (nil, true, true),
            (false, nil, true),
            (false, false, true),
            (false, true, true),
            (true, nil, true),
            (true, false, true),
            (true, true, false),
        ]
        for platform in CollectionPlatformAvailability.Platform.allCases {
            for (iosOnly, generativeOnly, availableOutsideIOS) in cases {
                XCTAssertEqual(
                    CollectionPlatformAvailability.isAvailable(
                        iosOnly: iosOnly,
                        generativeOnly: generativeOnly,
                        on: platform
                    ),
                    platform == .iOS || availableOutsideIOS
                )
            }
        }
    }

    func testRendererCollectionRestrictionsAcrossPlatforms() {
        let restrictions: [(String, Set<CollectionPlatformAvailability.Platform>)] = [
            ("0x0a1bbd57033f57e7b6743621b79fcb9eb2ce367650", [.visionOS]),
            ("0x0a1bbd57033f57e7b6743621b79fcb9eb2ce367667", [.visionOS]),
            ("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270250", [.visionOS, .tvOS]),
            ("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270356", [.visionOS, .tvOS]),
            ("0x99a9b7c1116f9ceeb1652de04d5969cce509b069472", [.visionOS, .tvOS]),
            ("unknown", []),
        ]
        for (collectionId, disabledPlatforms) in restrictions {
            for platform in CollectionPlatformAvailability.Platform.allCases {
                XCTAssertEqual(
                    CollectionPlatformAvailability.isRendererAvailable(
                        collectionId: collectionId,
                        isNative: false,
                        on: platform
                    ),
                    !disabledPlatforms.contains(platform),
                    "\(collectionId) on \(platform)"
                )
            }
        }
    }

    func testNativeRenderersAreAvailableOnlyOnIOSAndMacOS() {
        for platform in CollectionPlatformAvailability.Platform.allCases {
            XCTAssertEqual(
                CollectionPlatformAvailability.isRendererAvailable(
                    collectionId: "native",
                    isNative: true,
                    on: platform
                ),
                platform == .iOS || platform == .macOS
            )
        }
    }
}
