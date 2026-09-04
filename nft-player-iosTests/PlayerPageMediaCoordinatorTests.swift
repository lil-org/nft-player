import UIKit
import XCTest
@testable import nft_player_ios

nonisolated final class PlayerPageMediaCoordinatorTests: XCTestCase {}

@MainActor
extension PlayerPageMediaCoordinatorTests {
    func testClearRejectsOldReadinessAndRemovesCacheObservation() async throws {
        let fixture = PageMediaFixture()
        let coordinator = fixture.makeCoordinator()
        let rendered = expectation(description: "Local content rendered")
        fixture.renderer.onLocalContent = { rendered.fulfill() }
        coordinator.render(fixture.request())
        await fulfillment(of: [rendered], timeout: 1)
        let content = try XCTUnwrap(fixture.renderer.localContents.last)

        coordinator.clear()
        let readsAfterClear = fixture.localFileReadCount
        fixture.publishAvailability()
        let accepted = await content.success?()

        XCTAssertEqual(accepted, false)
        XCTAssertEqual(fixture.localFileReadCount, readsAfterClear)
        XCTAssertEqual(fixture.renderer.clearCount, 1)
        XCTAssertEqual(fixture.renderer.localContents.count, 1)
    }

    func testReplacedFileRejectsOldReadinessAndRendersNewVersion() async throws {
        let fixture = PageMediaFixture()
        let coordinator = fixture.makeCoordinator()
        let firstRender = expectation(description: "First local version")
        fixture.renderer.onLocalContent = { firstRender.fulfill() }
        coordinator.render(fixture.request())
        await fulfillment(of: [firstRender], timeout: 1)
        let original = try XCTUnwrap(fixture.renderer.localContents.last)

        fixture.revision = 2
        let replacementRender = expectation(description: "Replacement local version")
        fixture.renderer.onLocalContent = { replacementRender.fulfill() }
        let acceptedOriginal = await original.success?()
        await fulfillment(of: [replacementRender], timeout: 1)
        let replacement = try XCTUnwrap(fixture.renderer.localContents.last)
        let acceptedReplacement = await replacement.success?()

        XCTAssertEqual(acceptedOriginal, false)
        XCTAssertEqual(acceptedReplacement, true)
        XCTAssertEqual(fixture.renderer.invalidations, 1)
        XCTAssertEqual(fixture.renderer.localContents.count, 2)
    }

    func testFailureKeepsThumbnailAndRetriesOnlyAfterFileVersionChanges() async throws {
        let fixture = PageMediaFixture()
        fixture.cachedThumbnail = fixture.thumbnailImage
        let coordinator = fixture.makeCoordinator()
        let firstRender = expectation(description: "Initial local render")
        fixture.renderer.onLocalContent = { firstRender.fulfill() }
        coordinator.render(fixture.request())
        await fulfillment(of: [firstRender], timeout: 1)
        let original = try XCTUnwrap(fixture.renderer.localContents.last)
        await original.failure?()
        XCTAssertTrue(fixture.renderer.displayedImages.last === fixture.thumbnailImage)
        XCTAssertTrue(fixture.renderer.webContents.isEmpty)

        let unchangedVersionRead = expectation(description: "Unchanged version checked")
        fixture.onVersionRead = { unchangedVersionRead.fulfill() }
        fixture.publishAvailability()
        await fulfillment(of: [unchangedVersionRead], timeout: 1)
        XCTAssertEqual(fixture.renderer.localContents.count, 1)

        fixture.onVersionRead = nil
        fixture.revision = 2
        let replacementRender = expectation(description: "Changed version retried")
        fixture.renderer.onLocalContent = { replacementRender.fulfill() }
        fixture.publishAvailability()
        await fulfillment(of: [replacementRender], timeout: 1)
        XCTAssertEqual(fixture.renderer.localContents.count, 2)
    }

    func testFailureWithoutThumbnailFallsBackAndStopsObserving() async throws {
        let fixture = PageMediaFixture()
        let coordinator = fixture.makeCoordinator()
        let rendered = expectation(description: "Local content rendered")
        fixture.renderer.onLocalContent = { rendered.fulfill() }
        coordinator.render(fixture.request())
        await fulfillment(of: [rendered], timeout: 1)
        await fixture.renderer.localContents.last?.failure?()
        let readsAfterFallback = fixture.localFileReadCount
        fixture.publishAvailability()

        XCTAssertEqual(fixture.renderer.webContents, ["fallback"])
        XCTAssertEqual(fixture.localFileReadCount, readsAfterFallback)
        XCTAssertEqual(fixture.metrics.last?.value, .viewport)
    }

    func testLateThumbnailDoesNotCoverReadyMedia() async throws {
        let fixture = PageMediaFixture()
        let gate = PageMediaGate()
        let started = expectation(description: "Thumbnail loading")
        let finished = expectation(description: "Thumbnail completed after cancellation")
        fixture.imageLoader = { _, _ in
            started.fulfill()
            await gate.wait()
            finished.fulfill()
            return fixture.thumbnailImage
        }
        let coordinator = fixture.makeCoordinator()
        let rendered = expectation(description: "Local content rendered")
        fixture.renderer.onLocalContent = { rendered.fulfill() }
        coordinator.render(fixture.request())
        await fulfillment(of: [started, rendered], timeout: 1)
        let accepted = await fixture.renderer.localContents.last?.success?()
        XCTAssertEqual(accepted, true)

        await gate.release()
        await fulfillment(of: [finished], timeout: 1)
        XCTAssertTrue(fixture.renderer.provisionalImages.isEmpty)
        XCTAssertTrue(fixture.renderer.displayedImages.isEmpty)
    }

    func testThumbnailAppearsOverPendingLocalContent() async throws {
        let fixture = PageMediaFixture()
        fixture.imageLoader = { _, _ in fixture.thumbnailImage }
        let coordinator = fixture.makeCoordinator()
        let provisional = expectation(description: "Provisional image displayed")
        let rendered = expectation(description: "Local content rendered")
        fixture.renderer.onProvisionalImage = { provisional.fulfill() }
        fixture.renderer.onLocalContent = { rendered.fulfill() }
        coordinator.render(fixture.request())
        await fulfillment(of: [provisional, rendered], timeout: 1)

        XCTAssertTrue(fixture.renderer.provisionalImages.last === fixture.thumbnailImage)
        let accepted = await fixture.renderer.localContents.last?.success?()
        XCTAssertEqual(accepted, true)
    }

    func testClearingDuringMetadataLoadPreventsLateRender() async {
        let fixture = PageMediaFixture()
        let gate = PageMediaGate()
        let started = expectation(description: "Metadata loading")
        let finished = expectation(description: "Cancelled metadata returned")
        fixture.versionLoader = { url, descriptor in
            started.fulfill()
            await gate.wait()
            finished.fulfill()
            return fixture.version(url: url, descriptor: descriptor)
        }
        let coordinator = fixture.makeCoordinator()
        coordinator.render(fixture.request())
        await fulfillment(of: [started], timeout: 1)
        coordinator.clear()
        await gate.release()
        await fulfillment(of: [finished], timeout: 1)

        XCTAssertTrue(fixture.renderer.localContents.isEmpty)
        XCTAssertEqual(fixture.renderer.clearCount, 1)
    }

    func testReturningToSameDescriptorRejectsEarlierPresentationCallbacks() async throws {
        let fixture = PageMediaFixture()
        let coordinator = fixture.makeCoordinator()
        let firstRender = expectation(description: "First presentation")
        fixture.renderer.onLocalContent = { firstRender.fulfill() }
        coordinator.render(fixture.request())
        await fulfillment(of: [firstRender], timeout: 1)
        let first = try XCTUnwrap(fixture.renderer.localContents.last)
        coordinator.render(.web("another page"))

        let secondRender = expectation(description: "Same descriptor presented again")
        fixture.renderer.onLocalContent = { secondRender.fulfill() }
        coordinator.render(fixture.request())
        await fulfillment(of: [secondRender], timeout: 1)
        let second = try XCTUnwrap(fixture.renderer.localContents.last)
        let acceptedOld = await first.success?()
        let acceptedNew = await second.success?()

        XCTAssertEqual(acceptedOld, false)
        XCTAssertEqual(acceptedNew, true)
    }

    func testAdjacentArrivalPreloadsWithoutRestartingCurrentMedia() async {
        let fixture = PageMediaFixture()
        let coordinator = fixture.makeCoordinator()
        let rendered = expectation(description: "Current content rendered")
        fixture.renderer.onLocalContent = { rendered.fulfill() }
        coordinator.render(fixture.request(adjacentDescriptor: fixture.adjacent))
        await fulfillment(of: [rendered], timeout: 1)
        let accepted = await fixture.renderer.localContents.last?.success?()
        XCTAssertEqual(accepted, true)

        let adjacentURL = URL(fileURLWithPath: "/tmp/player-media-adjacent.gif")
        fixture.files[fixture.adjacent] = adjacentURL
        fixture.publishAvailability()
        fixture.publishAvailability()

        XCTAssertEqual(fixture.renderer.preloadedURLs, [adjacentURL])
        XCTAssertEqual(fixture.renderer.localContents.count, 1)
    }

    func testImageReplacementPreservesZoomAndOldCallbacksAreIgnored() throws {
        let fixture = PageMediaFixture()
        let coordinator = fixture.makeCoordinator()
        coordinator.render(.image(fixture.descriptor, fallbackHTML: "fallback"))
        let image = try XCTUnwrap(fixture.renderer.imagePresentation)
        image.onProvisional?(fixture.thumbnailImage)
        XCTAssertEqual(fixture.metrics.last?.policy, .reset)
        fixture.isZooming = true
        XCTAssertFalse(image.shouldAnimate())
        image.onLoaded?(fixture.thumbnailImage)
        XCTAssertEqual(fixture.metrics.last?.policy, .preserveActiveZoom)

        coordinator.clear()
        let metricsAfterClear = fixture.metrics.count
        image.onLoaded?(fixture.thumbnailImage)
        image.fallback()
        XCTAssertEqual(fixture.metrics.count, metricsAfterClear)
        XCTAssertTrue(fixture.renderer.webContents.isEmpty)
    }

    func testVideoMetricsDeferWhileZoomingAndCanBeReappliedFromCache() async {
        let fixture = PageMediaFixture()
        fixture.isZooming = true
        let size = CGSize(width: 1920, height: 1080)
        fixture.videoSize = size
        let measured = expectation(description: "Video dimensions measured")
        fixture.onMetrics = { value, policy in
            if value == .staticImage(size), policy == .deferWhileZooming {
                measured.fulfill()
            }
        }
        let coordinator = fixture.makeCoordinator()
        coordinator.render(fixture.request(kind: .video))
        await fulfillment(of: [measured], timeout: 1)
        fixture.onMetrics = nil
        fixture.isZooming = false
        coordinator.reapplyCurrentVideoMetrics()

        XCTAssertEqual(fixture.metrics.last?.value, .staticImage(size))
        XCTAssertEqual(fixture.metrics.last?.policy, .deferWhileZooming)
        XCTAssertEqual(fixture.videoSizeReadCount, 1)
    }

    func testHTMLDocumentUsesPreparedViewportAndRestrictedReadAccess() async throws {
        let fixture = PageMediaFixture()
        let size = CGSize(width: 600, height: 400)
        fixture.document = DownloadableTokenHTMLDocument(html: "prepared document", viewportSize: size)
        let coordinator = fixture.makeCoordinator()
        let rendered = expectation(description: "Prepared HTML rendered")
        fixture.renderer.onLocalContent = { rendered.fulfill() }
        coordinator.render(fixture.request(kind: .htmlDocument))
        await fulfillment(of: [rendered], timeout: 1)
        let content = try XCTUnwrap(fixture.renderer.localContents.last)

        XCTAssertEqual(content.html, "prepared document")
        XCTAssertEqual(content.readAccessURL, fixture.htmlDirectoryURL)
        XCTAssertEqual(fixture.metrics.last?.value, .staticImage(size))
        XCTAssertEqual(fixture.metrics.last?.policy, .preserveActiveZoom)
    }

    func testNativeCardAndCachedImageReportTheirContentBounds() {
        let fixture = PageMediaFixture()
        let coordinator = fixture.makeCoordinator()
        coordinator.render(.nativeCard(tokenId: "42", kind: .cardNft2, descriptor: nil))
        XCTAssertEqual(fixture.metrics.last?.value, .nativeCard)
        XCTAssertEqual(fixture.renderer.nativeTokenIDs, ["42"])

        coordinator.displayCachedImage(fixture.thumbnailImage, descriptor: fixture.descriptor)
        XCTAssertEqual(fixture.metrics.last?.value, .staticImage(fixture.thumbnailImage.size))
        XCTAssertEqual(fixture.metrics.last?.policy, .reset)
    }
}

private actor PageMediaGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var isReleased = false

    func wait() async {
        guard !isReleased else { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func release() {
        isReleased = true
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
private final class PageMediaFixture {
    typealias Coordinator = PlayerPageMediaCoordinator
    struct Metrics {
        let value: Coordinator.ContentMetrics
        let policy: Coordinator.ReplacementPolicy
    }

    let renderer = PageMediaRendererSpy()
    let notificationCenter = NotificationCenter()
    let descriptor = makeDescriptor(index: 0)
    let thumbnail = makeDescriptor(index: 10)
    let adjacent = makeDescriptor(index: 1)
    let htmlDirectoryURL = URL(fileURLWithPath: "/tmp/player-media-html")
    let thumbnailImage = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 30)).image { _ in }
    var files: [DownloadableMediaDescriptor: URL]
    var cachedThumbnail: UIImage?
    var revision = 1
    var localFileReadCount = 0
    var videoSizeReadCount = 0
    var isZooming = false
    var videoSize: CGSize?
    var document: DownloadableTokenHTMLDocument?
    var metrics = [Metrics]()
    var imageLoader: ((DownloadableMediaDescriptor, DownloadableMediaRequestPriority) async -> UIImage?)?
    var versionLoader: ((URL, DownloadableMediaDescriptor) async -> Coordinator.LocalMediaFileVersion)?
    var onVersionRead: (() -> Void)?
    var onMetrics: ((Coordinator.ContentMetrics, Coordinator.ReplacementPolicy) -> Void)?

    init() {
        files = [descriptor: URL(fileURLWithPath: "/tmp/player-media-current.gif")]
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            renderer: renderer,
            dependencies: .init(
                thumbnailDescriptor: { _ in self.thumbnail },
                cachedImage: { _ in self.cachedThumbnail },
                image: { descriptor, priority in await self.imageLoader?(descriptor, priority) },
                knownLocalFileURL: {
                    self.localFileReadCount += 1
                    return self.files[$0]
                },
                existingFileURL: { self.files[$0] },
                fileVersion: { url, descriptor in
                    self.onVersionRead?()
                    if let loader = self.versionLoader {
                        return await loader(url, descriptor)
                    }
                    return self.version(url: url, descriptor: descriptor)
                },
                imageSize: { _ in nil },
                videoSize: { _ in
                    self.videoSizeReadCount += 1
                    return self.videoSize
                },
                downloadedSourceURL: { _ in URL(string: "https://example.com/source.html")! },
                renderDocument: { _, _ in self.document },
                htmlDirectoryURL: htmlDirectoryURL,
                readAccessURL: URL(fileURLWithPath: "/tmp/player-media")
            ),
            notificationCenter: notificationCenter,
            onContentMetrics: { value, policy in
                self.metrics.append(Metrics(value: value, policy: policy))
                self.onMetrics?(value, policy)
            },
            hasActiveZoomTransform: { self.isZooming }
        )
    }

    func request(
        adjacentDescriptor: DownloadableMediaDescriptor? = nil,
        kind: DownloadableWebMediaKind = .image
    ) -> Coordinator.Request {
        .downloadableWebMedia(
            descriptor,
            adjacentDescriptor: adjacentDescriptor,
            fallbackHTML: "fallback",
            kind: kind
        )
    }

    func version(url: URL, descriptor: DownloadableMediaDescriptor) -> Coordinator.LocalMediaFileVersion {
        .init(fileURL: url, descriptor: descriptor, fileSize: revision, contentModificationDate: nil)
    }

    func publishAvailability() {
        notificationCenter.post(name: .downloadableMediaCacheFileAvailabilityDidChange, object: nil)
    }

    private static func makeDescriptor(index: Int) -> DownloadableMediaDescriptor {
        DownloadableMediaDescriptor(
            collectionId: "page-media-tests",
            tokenId: String(index),
            tokenIndex: index,
            media: .animatedImage(
                url: URL(string: "https://example.com/\(index).gif")!,
                fileExtension: "gif"
            )
        )
    }
}

@MainActor
private final class PageMediaRendererSpy: PlayerPageMediaRendering {
    struct LocalContent {
        let html: String
        let readAccessURL: URL
        let success: (() async -> Bool)?
        let failure: (() async -> Void)?
    }

    struct ImagePresentation {
        let onProvisional: ((UIImage) -> Void)?
        let onLoaded: ((UIImage) -> Void)?
        let shouldAnimate: () -> Bool
        let fallback: () -> Void
    }

    var localContents = [LocalContent]()
    var displayedImages = [UIImage]()
    var provisionalImages = [UIImage]()
    var webContents = [String]()
    var preloadedURLs = [URL]()
    var nativeTokenIDs = [String]()
    var clearCount = 0
    var invalidations = 0
    var imagePresentation: ImagePresentation?
    var onLocalContent: (() -> Void)?
    var onProvisionalImage: (() -> Void)?

    func clearContent() { clearCount += 1 }
    func invalidateLocalWebContentLoad() { invalidations += 1 }
    func displayLoadedImage(_ image: UIImage, key: DownloadableMediaDescriptor) {
        displayedImages.append(image)
    }
    func displayProvisionalImageOverLoadingWebContent(_ image: UIImage) {
        provisionalImages.append(image)
        onProvisionalImage?()
    }
    func renderImage(
        key: DownloadableMediaDescriptor,
        hideImageUntilLoaded: Bool,
        provisionalImage: UIImage?,
        loadProvisionalImage: ((@escaping (UIImage?) -> Void) -> (() -> Void)?)?,
        onBegin: (() -> Void)?,
        load: (@escaping (UIImage?) -> Void) -> (() -> Void)?,
        fallbackToWebContent: @escaping () -> Void,
        shouldAnimateLoadedImageReplacement: @escaping () -> Bool,
        onDisplayedProvisionalImage: ((UIImage) -> Void)?,
        onLoadedImage: ((UIImage) -> Void)?,
        onSuccess: (() -> Void)?
    ) {
        imagePresentation = ImagePresentation(
            onProvisional: onDisplayedProvisionalImage,
            onLoaded: onLoadedImage,
            shouldAnimate: shouldAnimateLoadedImageReplacement,
            fallback: fallbackToWebContent
        )
    }
    func renderWebContent(_ html: String, hidesEmptyWebContent: Bool, onBegin: (() -> Void)?) {
        webContents.append(html)
        onBegin?()
    }
    func renderLocalWebContent(
        _ html: String,
        contentKind: DownloadableWebMediaKind,
        htmlDirectoryURL: URL,
        readAccessURL: URL,
        hidesEmptyWebContent: Bool,
        provisionalImage: UIImage?,
        onBegin: (() -> Void)?,
        onLoadSuccess: (() async -> Bool)?,
        onLoadFailure: (() async -> Void)?
    ) {
        localContents.append(LocalContent(
            html: html,
            readAccessURL: readAccessURL,
            success: onLoadSuccess,
            failure: onLoadFailure
        ))
        onLocalContent?()
    }
    func renderNativeMetalCard(
        tokenId: String,
        renderKind: NativeMetalCardRenderKind,
        provisionalImage: UIImage?,
        loadProvisionalImage: ((@escaping (UIImage?) -> Void) -> (() -> Void)?)?
    ) {
        nativeTokenIDs.append(tokenId)
    }
    func preloadWebImage(_ imageURL: URL, completion: ((Bool) -> Void)?) {
        preloadedURLs.append(imageURL)
        completion?(true)
    }
}
