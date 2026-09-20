import Foundation
import XCTest
@testable import NftPlayerSyncCore

final class WidgetSelectionTests: XCTestCase {
    func testEmptyManifestHasNoImage() throws {
        let payload = try payload(#"{"version":2,"count":0,"firstId":"0"}"#)
        var generator = LastIndexGenerator()

        XCTAssertEqual(payload.count, 0)
        XCTAssertNil(payload.randomStaticImageReference(collection: try collection(), using: &generator))
        XCTAssertEqual(generator.calls, 0)
    }

    func testUnsupportedManifestExhaustsCandidates() throws {
        let payload = try payload("""
            {"version":2,"count":3,"firstId":"0",
            "urlSuffix":["file:///0.png","file:///1.png","file:///2.png"]}
            """)
        var generator = LastIndexGenerator()

        XCTAssertNil(payload.randomStaticImageReference(collection: try collection(), using: &generator))
        XCTAssertGreaterThan(generator.calls, 0)
        XCTAssertLessThanOrEqual(generator.calls, payload.count)
    }

    func testSelectionSkipsInvalidCandidateAndPreservesManifestPosition() throws {
        let payload = try payload("""
            {"version":2,"count":3,"ids":["mint-c","mint-a","mint-b"],
            "urlSuffix":[null,null,"file:///invalid.png"]}
            """)
        var generator = LastIndexGenerator()
        let reference = try XCTUnwrap(payload.randomStaticImageReference(
            collection: try collection(),
            using: &generator
        ))

        XCTAssertEqual(generator.calls, 2)
        XCTAssertEqual(reference.tokenId, "mint-a")
        XCTAssertEqual(reference.url.absoluteString, "https://cdn.lil.org/player/artwork/mid/1.webp")
        XCTAssertEqual(payload.item(at: 1).sourceIndex, 1)
    }

    func testIndexTemplatesPreserveCustomIDsAndFilenames() throws {
        for (template, filename) in [("index0", "1"), ("index1", "2")] {
            let payload = try payload("""
                {"version":2,"count":2,"ids":["mint-999","mint-42"],
                "urlTemplate":{"value":"\(template)","suffix":".png"}}
                """)
            var generator = LastIndexGenerator()
            let reference = try XCTUnwrap(payload.randomStaticImageReference(
                collection: try collection([
                    "urlPrefix": "https://cdn.lil.org/artwork/",
                    "standardThumbsPathsAvailable": true,
                ]),
                using: &generator
            ))

            XCTAssertEqual(generator.calls, 1)
            XCTAssertEqual(reference.tokenId, "mint-42")
            XCTAssertEqual(reference.url.absoluteString, "https://cdn.lil.org/artwork/mid/\(filename).webp")
        }
    }

    func testLargeCompactRangeSelectsOneItem() throws {
        let payload = try payload(#"{"version":2,"count":38965,"firstId":"123000000"}"#)
        var generator = LastIndexGenerator()
        let reference = try XCTUnwrap(payload.randomStaticImageReference(
            collection: try collection(),
            using: &generator
        ))

        XCTAssertEqual(payload.count, 38_965)
        XCTAssertEqual(generator.calls, 1)
        XCTAssertEqual(reference.tokenId, "123038964")
        XCTAssertEqual(reference.url.absoluteString, "https://cdn.lil.org/player/artwork/mid/38964.webp")
    }

    private func payload(_ json: String) throws -> WidgetTokenPayload {
        try JSONDecoder().decode(WidgetTokenPayload.self, from: Data(json.utf8))
    }

    private func collection(_ fields: [String: Any] = [:]) throws -> WidgetCollection {
        var values: [String: Any] = [
            "address": "collection",
            "chain": "solana",
            "internal_slug": "artwork",
            "script": ["kind": "js"],
        ]
        values.merge(fields) { _, replacement in replacement }
        return try JSONDecoder().decode(
            WidgetCollection.self,
            from: JSONSerialization.data(withJSONObject: values)
        )
    }

    private struct LastIndexGenerator: RandomNumberGenerator {
        var calls = 0

        mutating func next() -> UInt64 {
            calls += 1
            return .max
        }
    }
}
