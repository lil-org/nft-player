// ∅ 2026 lil org

import XCTest
@testable import NftPlayerSyncCore

@MainActor
final class WidgetDeepLinkTests: XCTestCase {

    func testCollectionOnlyLinkRoundTrips() throws {
        let link = WidgetDeepLink.collection(id: "collection", tokenId: nil)

        let url = try XCTUnwrap(link.url)

        XCTAssertEqual(WidgetDeepLink(url: url), link)
        XCTAssertEqual(collectionId(in: url), "collection")
        XCTAssertNil(tokenId(in: url))
    }

    func testCollectionTokenLinkRoundTrips() throws {
        let link = WidgetDeepLink.collection(id: "collection", tokenId: "token-10")

        let url = try XCTUnwrap(link.url)

        XCTAssertEqual(WidgetDeepLink(url: url), link)
        XCTAssertEqual(collectionId(in: url), "collection")
        XCTAssertEqual(tokenId(in: url), "token-10")
    }

    func testOldCollectionOnlyURLStillParses() throws {
        let url = try XCTUnwrap(URL(string: "nft-folder://collection?id=collection"))

        XCTAssertEqual(WidgetDeepLink(url: url), .collection(id: "collection", tokenId: nil))
    }

    func testEmptyTokenIdParsesAsCollectionOnly() throws {
        let url = try XCTUnwrap(URL(string: "nft-folder://collection?id=collection&tokenId="))

        XCTAssertEqual(WidgetDeepLink(url: url), .collection(id: "collection", tokenId: nil))
    }

    func testCollectionTargetRequiresSupportedCollection() throws {
        let deepLink = try XCTUnwrap(
            WidgetDeepLink(
                url: try XCTUnwrap(
                    URL(string: "nft-folder://collection?id=collection&tokenId=token-10")
                )
            )
        )

        XCTAssertNil(deepLink.collectionTarget(ifSupported: { _ in false }))
        XCTAssertEqual(
            deepLink.collectionTarget(ifSupported: { $0 == "collection" }),
            WidgetCollectionDeepLinkTarget(
                collectionId: "collection",
                tokenId: "token-10"
            )
        )
    }

    func testInitialWidgetURLSuppressesContinueViewingUntilHandoffFinishes() throws {
        let state = WidgetLaunchPresentationState()
        let url = try XCTUnwrap(WidgetDeepLink.collection(id: "collection", tokenId: nil).url)

        state.prepareForIncomingURLs(
            [url],
            isApplicationLaunch: true,
            isSupportedCollection: { $0 == "collection" }
        )

        XCTAssertTrue(state.isSuppressingContinueViewing)

        let request = state.beginWidgetPlayerHandoff(for: url)
        state.finishWidgetPlayerHandoff(request)

        XCTAssertFalse(state.isSuppressingContinueViewing)
    }

    func testSupersededDuplicateHandoffCannotClearSuppression() throws {
        let state = WidgetLaunchPresentationState()
        let url = try XCTUnwrap(WidgetDeepLink.collection(id: "collection", tokenId: nil).url)
        state.prepareForIncomingURLs(
            [url],
            isApplicationLaunch: true,
            isSupportedCollection: { $0 == "collection" }
        )
        let firstRequest = state.beginWidgetPlayerHandoff(for: url)
        let replacementRequest = state.beginWidgetPlayerHandoff(for: url)

        state.finishWidgetPlayerHandoff(firstRequest)

        XCTAssertTrue(state.isSuppressingContinueViewing)

        state.finishWidgetPlayerHandoff(replacementRequest)

        XCTAssertFalse(state.isSuppressingContinueViewing)
    }

    func testWarmWidgetURLDoesNotSuppressContinueViewing() throws {
        let state = WidgetLaunchPresentationState()
        let url = try XCTUnwrap(WidgetDeepLink.collection(id: "collection", tokenId: nil).url)

        state.prepareForIncomingURLs(
            [url],
            isApplicationLaunch: false,
            isSupportedCollection: { $0 == "collection" }
        )

        XCTAssertFalse(state.isSuppressingContinueViewing)
    }

    func testNormalLaunchDoesNotSuppressContinueViewing() {
        let state = WidgetLaunchPresentationState()

        state.prepareForIncomingURLs(
            [],
            isApplicationLaunch: true,
            isSupportedCollection: { _ in true }
        )

        XCTAssertFalse(state.isSuppressingContinueViewing)
    }

    func testMalformedInitialURLDoesNotSuppressContinueViewing() throws {
        let state = WidgetLaunchPresentationState()
        let url = try XCTUnwrap(URL(string: "https://example.com/collection?id=collection"))

        state.prepareForIncomingURLs(
            [url],
            isApplicationLaunch: true,
            isSupportedCollection: { _ in true }
        )

        XCTAssertFalse(state.isSuppressingContinueViewing)
    }

    func testUnsupportedInitialWidgetURLDoesNotSuppressContinueViewing() throws {
        let state = WidgetLaunchPresentationState()
        let url = try XCTUnwrap(WidgetDeepLink.collection(id: "stale-collection", tokenId: nil).url)

        state.prepareForIncomingURLs(
            [url],
            isApplicationLaunch: true,
            isSupportedCollection: { $0 == "collection" }
        )

        XCTAssertFalse(state.isSuppressingContinueViewing)
    }

    func testUnrelatedURLDoesNotFinishPendingHandoff() throws {
        let state = WidgetLaunchPresentationState()
        let pendingURL = try XCTUnwrap(WidgetDeepLink.collection(id: "collection", tokenId: nil).url)
        let unrelatedURL = try XCTUnwrap(WidgetDeepLink.collection(id: "other", tokenId: nil).url)
        state.prepareForIncomingURLs(
            [pendingURL],
            isApplicationLaunch: true,
            isSupportedCollection: { $0 == "collection" }
        )

        state.finishWidgetPlayerHandoff(for: unrelatedURL)

        XCTAssertTrue(state.isSuppressingContinueViewing)
    }

    func testMultiplePendingHandoffsFinishIndependently() throws {
        let state = WidgetLaunchPresentationState()
        let firstURL = try XCTUnwrap(WidgetDeepLink.collection(id: "first", tokenId: nil).url)
        let secondURL = try XCTUnwrap(WidgetDeepLink.collection(id: "second", tokenId: nil).url)
        state.prepareForIncomingURLs(
            [firstURL, secondURL],
            isApplicationLaunch: true,
            isSupportedCollection: { _ in true }
        )

        state.finishWidgetPlayerHandoff(for: firstURL)

        XCTAssertTrue(state.isSuppressingContinueViewing)

        state.finishWidgetPlayerHandoff(for: secondURL)

        XCTAssertFalse(state.isSuppressingContinueViewing)
    }

    func testEquivalentURLFinishesPendingHandoff() throws {
        let state = WidgetLaunchPresentationState()
        let preparedURL = try XCTUnwrap(
            URL(string: "nft-folder://collection?id=collection&tokenId=token-10")
        )
        let deliveredURL = try XCTUnwrap(
            URL(string: "nft-folder://collection?tokenId=token-10&id=collection")
        )
        state.prepareForIncomingURLs(
            [preparedURL],
            isApplicationLaunch: true,
            isSupportedCollection: { $0 == "collection" }
        )

        state.finishWidgetPlayerHandoff(for: deliveredURL)

        XCTAssertFalse(state.isSuppressingContinueViewing)
    }

    func testCancelAllClearsPendingHandoffs() throws {
        let state = WidgetLaunchPresentationState()
        let url = try XCTUnwrap(WidgetDeepLink.collection(id: "collection", tokenId: nil).url)
        state.prepareForIncomingURLs(
            [url],
            isApplicationLaunch: true,
            isSupportedCollection: { $0 == "collection" }
        )

        state.cancelAllWidgetPlayerHandoffs()

        XCTAssertFalse(state.isSuppressingContinueViewing)
    }

    private func collectionId(in url: URL) -> String? {
        queryValue(named: "id", in: url)
    }

    private func tokenId(in url: URL) -> String? {
        queryValue(named: "tokenId", in: url)
    }

    private func queryValue(named name: String, in url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == name })?
            .value
    }
}
