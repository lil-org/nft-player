import Foundation
import XCTest
@testable import NftPlayerSyncCore

final class CollectionPreviewImageURLTests: XCTestCase {
    func testGenerativePreviewUsesOriginalManifestIndex() {
        XCTAssertEqual(
            CollectionBrowseImageURLMapping.generativeMidURL(slug: "hyperhash", sourceIndex: 7)?.absoluteString,
            "https://cdn.lil.org/player/hyperhash/mid/7.webp"
        )
        XCTAssertNil(CollectionBrowseImageURLMapping.generativeMidURL(slug: nil, sourceIndex: 7))
        XCTAssertNil(CollectionBrowseImageURLMapping.generativeMidURL(slug: "../other", sourceIndex: 7))
        XCTAssertNil(CollectionBrowseImageURLMapping.generativeMidURL(slug: "hyperhash", sourceIndex: nil))
        XCTAssertNil(CollectionBrowseImageURLMapping.generativeMidURL(slug: "hyperhash", sourceIndex: -1))
    }

    func testDownloadablePreviewPreservesOriginalFilename() throws {
        for fileExtension in ["png", "svg", "gif", "mp4", "html"] {
            let originalURL = try XCTUnwrap(URL(string: "https://cdn.lil.org/player/art/0007.\(fileExtension)?version=3#image"))
            XCTAssertEqual(
                CollectionBrowseImageURLMapping.downloadableMidURL(
                    for: originalURL,
                    standardThumbsPathsAvailable: true
                )?.absoluteString,
                "https://cdn.lil.org/player/art/mid/0007.webp"
            )
        }
    }

    func testTerraformsHTMLUsesCDNPreviewBase() throws {
        let originalURL = try XCTUnwrap(URL(string: "https://tokens.mathcastles.xyz/terraforms/token-html/42"))
        XCTAssertEqual(
            CollectionBrowseImageURLMapping.downloadableMidURL(
                for: originalURL,
                standardThumbsPathsAvailable: true,
                standardThumbsBaseURL: "https://cdn.lil.org/player/terraforms/thumbs/"
            )?.absoluteString,
            "https://cdn.lil.org/player/terraforms/mid/42.webp"
        )
    }

    func testDownloadablePreviewRequiresDeclaredCDNThumbnailPath() throws {
        let originalURL = try XCTUnwrap(URL(string: "https://cdn.lil.org/player/art/0007.png"))
        XCTAssertNil(CollectionBrowseImageURLMapping.downloadableMidURL(
            for: originalURL,
            standardThumbsPathsAvailable: false
        ))
        for base in ["https://other.example/thumbs/", "http://cdn.lil.org/thumbs/", "https://cdn.lil.org/previews/"] {
            XCTAssertNil(CollectionBrowseImageURLMapping.downloadableMidURL(
                for: originalURL,
                standardThumbsPathsAvailable: true,
                standardThumbsBaseURL: base
            ))
        }
    }
}
