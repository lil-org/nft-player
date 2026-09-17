import CoreGraphics
import Foundation
import ImageIO
import XCTest
@testable import NftPlayerSyncCore

private actor RecoveryCoverTransport {
    enum Failure: Error { case offline }

    private let image: Data
    private let bulkStarted: XCTestExpectation
    private var isAvailable = false
    private var holdsBulk = true
    private var bulkContinuation: CheckedContinuation<Void, Never>?
    private(set) var names: [String] = []

    init(image: Data, bulkStarted: XCTestExpectation) {
        self.image = image
        self.bulkStarted = bulkStarted
    }

    func fetch(_ url: URL) async throws -> (data: Data, statusCode: Int) {
        let name = url.deletingPathExtension().lastPathComponent
        names.append(name)
        guard isAvailable else { throw Failure.offline }
        if name == "bulk-first", holdsBulk {
            bulkStarted.fulfill()
            await withCheckedContinuation { bulkContinuation = $0 }
        }
        return (image, 200)
    }

    func restoreConnection() {
        isAvailable = true
    }

    func releaseBulk() {
        holdsBulk = false
        bulkContinuation?.resume()
        bulkContinuation = nil
    }
}

@MainActor
final class CollectionCoverRecoveryTests: XCTestCase {
    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CollectionCoverRecoveryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    private func jpeg() throws -> Data {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        let image = try XCTUnwrap(context.makeImage())
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    func testOnlyReconnectsPublishOnceOnTheMainThread() async throws {
        let cache = PersistentCollectionCoverCache(rootURL: try directory()) { _ in
            XCTFail("Path updates without cover demand should not download")
            throw RecoveryCoverTransport.Failure.offline
        }
        let recovery = CollectionCoverRecovery(cache: cache)
        let initiallyUnavailable = CollectionCoverRecovery(cache: cache)
        let unexpected = expectation(description: "Initial and repeated path states stay quiet")
        unexpected.isInverted = true
        let initialObserver = NotificationCenter.default.addObserver(
            forName: .collectionCoverConnectionRecovered, object: nil, queue: nil
        ) { notification in
            guard let source = notification.object as? CollectionCoverRecovery,
                  source === recovery || source === initiallyUnavailable else { return }
            unexpected.fulfill()
        }
        recovery.update(isAvailable: true)
        recovery.update(isAvailable: true)
        initiallyUnavailable.update(isAvailable: false)
        initiallyUnavailable.update(isAvailable: false)
        await fulfillment(of: [unexpected], timeout: 0.1)
        NotificationCenter.default.removeObserver(initialObserver)

        let firstReconnect = expectation(description: "First reconnection")
        firstReconnect.assertForOverFulfill = false
        let reconnects = expectation(description: "One event per reconnection")
        reconnects.expectedFulfillmentCount = 2
        reconnects.assertForOverFulfill = true
        let observer = NotificationCenter.default.addObserver(
            forName: .collectionCoverConnectionRecovered, object: nil, queue: nil
        ) { notification in
            guard notification.object as? CollectionCoverRecovery === recovery else { return }
            XCTAssertTrue(Thread.isMainThread)
            firstReconnect.fulfill()
            reconnects.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        recovery.update(isAvailable: false)
        recovery.update(isAvailable: false)
        recovery.update(isAvailable: true)
        recovery.update(isAvailable: true)
        await fulfillment(of: [firstReconnect], timeout: 2)
        recovery.update(isAvailable: false)
        recovery.update(isAvailable: false)
        recovery.update(isAvailable: true)
        recovery.update(isAvailable: true)
        await fulfillment(of: [reconnects], timeout: 2)
    }

    func testRecoveryNotificationRetriesFailedVisibleCoverAheadOfQueuedBulk() async throws {
        let image = try jpeg()
        let bulkStarted = expectation(description: "First bulk cover holds the background slot")
        let transport = RecoveryCoverTransport(image: image, bulkStarted: bulkStarted)
        let cache = PersistentCollectionCoverCache(rootURL: try directory()) {
            try await transport.fetch($0)
        }
        addTeardownBlock {
            await transport.releaseBulk()
            for name in ["bulk-first", "bulk-last"] {
                _ = try? await cache.data(for: name, priority: .background)
            }
        }
        do {
            _ = try await cache.data(for: "visible-cover")
            XCTFail("The first visible load should fail offline")
        } catch RecoveryCoverTransport.Failure.offline {}

        await transport.restoreConnection()
        await cache.preload(assetNames: ["bulk-first", "bulk-last"])
        await fulfillment(of: [bulkStarted], timeout: 2)
        let recovery = CollectionCoverRecovery(cache: cache)
        recovery.update(isAvailable: false)
        let recovered = expectation(description: "Visible consumer retries from recovery notification")
        recovered.assertForOverFulfill = true
        let observer = NotificationCenter.default.addObserver(
            forName: .collectionCoverConnectionRecovered, object: nil, queue: nil
        ) { notification in
            guard notification.object as? CollectionCoverRecovery === recovery else { return }
            XCTAssertTrue(Thread.isMainThread)
            Task {
                do {
                    let restored = try await cache.data(for: "visible-cover")
                    XCTAssertEqual(restored, image)
                } catch {
                    XCTFail("The visible cover should recover: \(error)")
                }
                recovered.fulfill()
            }
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        recovery.update(isAvailable: true)
        await fulfillment(of: [recovered], timeout: 2)
        let names = await transport.names
        XCTAssertEqual(names, ["visible-cover", "bulk-first", "visible-cover"])
    }
}
