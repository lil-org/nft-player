import Foundation
import UIKit
import WebKit
import XCTest
@testable import nft_player_ios

nonisolated final class ArtBlocksRenderingResolutionTests: CollectionTokenFixtureTestCase {}

@MainActor
private final class ResolutionDocumentProbe: NSObject, WKScriptMessageHandler {
    var documents: [[String: Any]] = []

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let document = message.body as? [String: Any],
              let generation = document["generation"] as? String,
              !documents.contains(where: { $0["generation"] as? String == generation }) else { return }
        documents.append(document)
    }
}

@MainActor
private final class ResolutionFixture {
    let webView: AutoReloadingWebView
    let window: UIWindow
    let probe = ResolutionDocumentProbe()
    let nativeScale: CGFloat
    var errors: [String] = []

    init(size: CGSize = CGSize(width: 300, height: 400), artBlocksRendering: Bool = true) throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        nativeScale = scene.screen.scale
        webView = artBlocksRendering ? AutoReloadingWebView.newArtBlocksRenderer() : AutoReloadingWebView.new
        webView.artworkDependencyCache = JavaScriptLibraryFixtures.cache
        webView.frame = CGRect(origin: CGPoint(x: 12, y: 60), size: size)
        webView.configuration.userContentController.add(probe, name: "resolutionDocumentProbe")
        webView.configuration.userContentController.addUserScript(WKUserScript(source: """
        const nativeCanvasWidth = Object.getOwnPropertyDescriptor(HTMLCanvasElement.prototype, 'width').get;
        const nativeCanvasHeight = Object.getOwnPropertyDescriptor(HTMLCanvasElement.prototype, 'height').get;
        window.__resolutionBitmapWidth = canvas => nativeCanvasWidth.call(canvas);
        window.__resolutionBitmapHeight = canvas => nativeCanvasHeight.call(canvas);
        document.addEventListener('DOMContentLoaded', function () {
          if (typeof tokenData === 'object' && tokenData) {
            window.__resolutionOriginalToken = { tokenId: tokenData.tokenId, hash: tokenData.hash || tokenData.hashes?.[0] };
          }
          window.webkit.messageHandlers.resolutionDocumentProbe.postMessage({
            generation: window.__artBlocksPreviewGeneration || 'production',
            tokenId: typeof tokenData === 'undefined' ? null : tokenData.tokenId,
            hash: typeof tokenData === 'undefined' ? null : tokenData.hash || tokenData.hashes?.[0]
          });
        }, { once: true });
        """, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let host = UIViewController()
        host.view.addSubview(webView)
        window = UIWindow(windowScene: scene)
        window.rootViewController = host
        window.isHidden = false
        window.layoutIfNeeded()
    }

    func load(_ script: Script, token: BundledTokens.Item, artBlocksRendering: Bool = true) {
        if artBlocksRendering {
            webView.configureArtBlocksRendering(collectionId: script.id, tokenId: token.id) { [weak self] in
                self?.errors.append($0)
            }
        }
        let observer = """
        <script>
        if(typeof p5!=="undefined") {
          p5.prototype.registerMethod("init",function(){(window.__resolutionInstances ||= []).push(this);});
          const originalCopy=p5.prototype.copy;
          p5.prototype.copy=function(){
            const source=arguments[0];
            if(source?.canvas) (window.__resolutionCopies ||= []).push({width:source.width,height:source.height,
              bitmapWidth:source.canvas.width,bitmapHeight:source.canvas.height});
            return originalCopy.apply(this,arguments);
          };
        }
        </script>
        """
        let html = RawHtmlGenerator.createHtml(script: script, token: token)
            .replacingOccurrences(of: "<script>" + script.value + "</script>", with: observer + "<script>" + script.value + "</script>")
        webView.loadHTMLString(html, baseURL: nil)
    }

    func close() {
        webView.stopLoading()
        webView.clearArtBlocksRendering()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "resolutionDocumentProbe")
        window.isHidden = true
        window.rootViewController = nil
    }

    func snapshot() async throws -> [String: Any] {
        let result = try await webView.evaluateJavaScript(Self.snapshotScript)
        return try XCTUnwrap(result as? [String: Any])
    }

    private static let snapshotScript = """
    (() => ({
      generation: window.__artBlocksPreviewGeneration || null,
      tokenId: typeof tokenData === 'object' && tokenData ? tokenData.tokenId : window.__resolutionOriginalToken?.tokenId,
      hash: typeof tokenData === 'object' && tokenData ? tokenData.hash || tokenData.hashes?.[0] : window.__resolutionOriginalToken?.hash,
      dpr: devicePixelRatio, width: innerWidth, height: innerHeight,
      viewportScale: window.visualViewport?.scale || 1,
      quality: window.__artBlocksPreviewResolution || null,
      canvases: [...document.querySelectorAll('canvas')].map(canvas => {
        const rect = canvas.getBoundingClientRect(), style = getComputedStyle(canvas);
        return { id: canvas.id, width: window.__resolutionBitmapWidth(canvas), height: window.__resolutionBitmapHeight(canvas),
          logicalWidth: canvas.width, logicalHeight: canvas.height, x: rect.x, y: rect.y,
          rectWidth: rect.width, rectHeight: rect.height, imageRendering: style.imageRendering,
          filter: style.filter, display: style.display };
      }),
      vahria: typeof composer === 'undefined' ? null : {
        buffer: [renderer.getDrawingBufferSize(new THREE.Vector2()).x, renderer.getDrawingBufferSize(new THREE.Vector2()).y],
        target: [composer.renderTarget1.width, composer.renderTarget1.height],
        ja: displacementShader.uniforms.ja.value, passJa: displacementPass.uniforms.ja.value
      }
    }))()
    """
}

@MainActor
extension ArtBlocksRenderingResolutionTests {
    func testAnUnusedDrawingContextDoesNotTriggerAResolutionReload() async throws {
        let fixture = try ResolutionFixture()
        defer { fixture.close() }
        let (script, token) = try syntheticScript(source: """
        const canvas = document.body.appendChild(document.createElement('canvas'));
        canvas.width = innerWidth; canvas.height = innerHeight;
        canvas.style.cssText = 'width:100vw;height:100vh';
        canvas.getContext('2d');
        """)
        fixture.load(script, token: token)
        try await waitUntil { fixture.probe.documents.count == 1 }
        try await Task.sleep(for: .milliseconds(1100))
        XCTAssertEqual(fixture.probe.documents.count, 1)
        let quality = try await fixture.webView.evaluateJavaScript("typeof window.__artBlocksPreviewResolution")
        XCTAssertEqual(quality as? String, "undefined")
    }

    func testALateDetailLayerIsRecheckedAfterTheInitialQualityReport() async throws {
        let fixture = try ResolutionFixture()
        defer { fixture.close() }
        let (script, token) = try syntheticScript(source: canvasSource(densityAware: true) + """
        setTimeout(function () {
          const detail = document.body.appendChild(document.createElement('canvas'));
          detail.id = 'late-detail'; detail.width = innerWidth / 3; detail.height = innerHeight / 3;
          detail.style.cssText = 'position:absolute;left:0;top:0;width:33.333333vw;height:33.333333vh';
          const context = detail.getContext('2d'); context.fillStyle = '#cc3535'; context.fillRect(0,0,detail.width,detail.height);
        }, 1100);
        """)
        fixture.load(script, token: token)
        try await waitForQuality(fixture, tokenId: token.id)
        try await waitUntil(timeout: 10) {
            guard fixture.probe.documents.count == 2,
                  let snapshot = try? await fixture.snapshot(),
                  let canvases = snapshot["canvases"] as? [[String: Any]],
                  let detail = canvases.first(where: { $0["id"] as? String == "late-detail" }) else { return false }
            return self.number(detail, "width") + 1 >= self.number(detail, "rectWidth") * self.number(snapshot, "dpr")
        }
        XCTAssertTrue(fixture.errors.isEmpty)
    }

    func testPixelatedLayerDoesNotSuppressAnOrdinaryUndersampledLayer() async throws {
        let fixture = try ResolutionFixture()
        defer { fixture.close() }
        let (script, token) = try syntheticScript(source: canvasSource(densityAware: false, style: "filter:blur(0px)") + """
        const pixels = document.body.appendChild(document.createElement('canvas'));
        pixels.id = 'intentional-pixels'; pixels.width = pixels.height = 32;
        pixels.style.cssText = 'position:absolute;inset:0;width:100vw;height:100vh;image-rendering:pixelated';
        pixels.getContext('2d').fillRect(0,0,32,32);
        """)
        fixture.load(script, token: token)
        try await waitForQuality(fixture, tokenId: token.id)
        XCTAssertEqual(fixture.probe.documents.count, 2)
        let snapshot = try await fixture.snapshot()
        let canvases = try XCTUnwrap(snapshot["canvases"] as? [[String: Any]])
        let pixels = try XCTUnwrap(canvases.first { $0["id"] as? String == "intentional-pixels" })
        XCTAssertEqual(number(pixels, "width"), 32)
        XCTAssertEqual(pixels["imageRendering"] as? String, "pixelated")
        XCTAssertTrue(fixture.errors.isEmpty)
    }

    func testOdeToRoyMaskKeepsRetinaPixelsAndLogicalPlacement() async throws {
        let script = Script(
            id: "0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd27063",
            address: "0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270", name: "Ode to Roy", abId: "63",
            value: """
            let ov, ma, im, cn = 0;
            function oP() {
              (im = ov.get()).mask(ma), image(im, -cn, -cn);
            }
            function setup() {
              createCanvas(100,100); noLoop();
              const source=ov=createGraphics(100,100), mask=ma=createGraphics(100,100);
              source.background(255,0,0); mask.noStroke(); mask.fill(255); mask.rect(0,0,50,100);
              background(0,0,255); blendMode(ADD);
              const drawImage=image;
              image=function(result,x,y,w,h){window.compositeSize=[result.canvas.width,result.canvas.height,x,y,w,h];return drawImage(result,x,y,w,h);};
              oP();
              window.maskPixels=[get(25,50),get(75,50)];
            }
            """,
            metadata: .init(kind: .p5js100, renderingProfile: .artBlocks)
        )
        let token = BundledTokens.Item(id: "63000000", name: nil, hash: "0x" + String(repeating: "a", count: 64))
        let fixture = try ResolutionFixture(size: CGSize(width: 100, height: 100))
        defer { fixture.close() }
        fixture.load(script, token: token)
        try await waitForQuality(fixture, tokenId: token.id)
        let size = try await fixture.webView.evaluateJavaScript("window.compositeSize")
        XCTAssertEqual(size as? [Double], [100 * Double(fixture.nativeScale), 100 * Double(fixture.nativeScale), 0, 0, 100, 100])
        let pixels = try await fixture.webView.evaluateJavaScript("window.maskPixels")
        XCTAssertEqual(pixels as? [[Int]], [[255,0,255,255],[0,0,255,255]])
        XCTAssertTrue(fixture.errors.isEmpty)
    }

    func testDenseCropPreservesPixelsAndTransparentCanvasEdges() async throws {
        let script = Script(
            id: "0x47a91457a3a1f700097199fd63c039c4784384ab315",
            address: "0x47a91457a3a1f700097199fd63c039c4784384ab", name: "Can you see it", abId: "315",
            value: """
            let numFields=1;
            function applyEffectsToFields() {
              const x=90,y=0,w=width,h=height;
              image(get(x, y, w, h /2), 0, -h / 2);
              if(numFields===0) image(get(x, y, w / 2, h), -w / 2, 0);
            }
            function setup() {
              createCanvas(100,100);noLoop();background(255,0,0);
              const originalImage=image;
              image=function(source){window.__denseCrop=source;return originalImage.apply(this,arguments);};
              applyEffectsToFields();
            }
            """,
            metadata: .init(kind: .p5js100, renderingProfile: .artBlocks)
        )
        let token = BundledTokens.Item(id: "17", name: nil, hash: "0x" + String(repeating: "a", count: 64))
        let fixture = try ResolutionFixture(size: CGSize(width: 100, height: 100))
        defer { fixture.close() }
        fixture.load(script, token: token)
        try await waitUntil { (try? await fixture.webView.evaluateJavaScript("!!window.__denseCrop")) as? Bool == true }
        let rawResult = try await fixture.webView.evaluateJavaScript("""
        (()=>{const c=window.__denseCrop,d=c.drawingContext;return {width:c.width,height:c.height,
          bitmapWidth:c.canvas.width,bitmapHeight:c.canvas.height,
          inside:Array.from(d.getImageData(1,1,1,1).data),outside:Array.from(d.getImageData(c.canvas.width-1,1,1,1).data)};})()
        """)
        let result = try XCTUnwrap(rawResult as? [String: Any])
        XCTAssertEqual(number(result, "width"), 100)
        XCTAssertEqual(number(result, "height"), 50)
        XCTAssertEqual(number(result, "bitmapWidth"), 100 * Double(fixture.nativeScale), accuracy: 1)
        XCTAssertEqual(number(result, "bitmapHeight"), 50 * Double(fixture.nativeScale), accuracy: 1)
        XCTAssertEqual(result["inside"] as? [Int], [255, 0, 0, 255])
        XCTAssertEqual(result["outside"] as? [Int], [0, 0, 0, 0])
        XCTAssertTrue(fixture.errors.isEmpty)
    }
    func testMuranoFantasyPreservesItsCachedImageResolution() async throws { try await verifyArtist("Murano Fantasy") }
    func testBauhausSynthesisPreservesItsCropResolution() async throws { try await verifyArtist("Bauhaus Synthesis") }
    func testCanYouSeeItPreservesItsReflectedFieldResolution() async throws { try await verifyArtist("Can you see it") }
    func testCushionsNinthTokenFinishesItsRegionColoring() async throws { try await verifyArtist("Cushions", tokenIndex: 8) }
    func testCushionsTwentyFirstTokenFinishesItsRegionColoring() async throws { try await verifyArtist("Cushions", tokenIndex: 20) }
    func testTimeTravelPreservesItsAlternateViewResolution() async throws { try await verifyArtist("Time travel in a subconscious mind") }
    func test100SunsetsUsesItsAuthoredDensityControl() async throws { try await verifyArtist("100 Sunsets") }
    func testBubbleBlobbyUsesItsAuthoredHighestQuality() async throws { try await verifyArtist("Bubble Blobby") }
    func testOdeToRoyRendersWithNativeBackingResolution() async throws { try await verifyArtist("Ode to Roy") }

    func testViewportCanvasRerendersAtNativeResolutionAndFillsTheView() async throws {
        let fixture = try ResolutionFixture()
        defer { fixture.close() }
        let (script, token) = try syntheticScript(source: canvasSource(densityAware: false))
        fixture.load(script, token: token)
        try await waitForQuality(fixture, tokenId: token.id)
        let expectedDocuments = fixture.nativeScale > 1.02 ? 2 : 1
        try await waitUntil { fixture.probe.documents.count == expectedDocuments }
        let snapshot = try await fixture.snapshot()
        let canvas = try largestCanvas(snapshot)
        assertNativeResolution(canvas, snapshot: snapshot)
        XCTAssertEqual(number(canvas, "rectWidth") * Double(fixture.webView.pageZoom) * number(snapshot, "viewportScale"), Double(fixture.webView.bounds.width), accuracy: 1)
        XCTAssertEqual(number(canvas, "rectHeight") * Double(fixture.webView.pageZoom) * number(snapshot, "viewportScale"), Double(fixture.webView.bounds.height), accuracy: 1)
        XCTAssertEqual(fixture.webView.pageZoom, 1 / fixture.nativeScale, accuracy: 0.02)
        XCTAssertTrue(fixture.probe.documents.allSatisfy { $0["tokenId"] as? String == token.id && $0["hash"] as? String == token.hash })
        try await assertStable(fixture, expectedDocuments: expectedDocuments)
        XCTAssertTrue(fixture.errors.isEmpty, fixture.errors.joined(separator: "; "))
    }

    func testLetterboxedFullscreenSquareGetsNativePixelsWithoutChangingItsSize() async throws {
        let fixture = try ResolutionFixture(size: CGSize(width: 844, height: 390))
        defer { fixture.close() }
        let (script, token) = try syntheticScript(source: """
        const side = Math.min(innerWidth, innerHeight);
        const canvas = document.body.appendChild(document.createElement('canvas'));
        canvas.width = canvas.height = side;
        canvas.style.width = canvas.style.height = side + 'px';
        const context = canvas.getContext('2d');
        context.fillStyle = '#237b43'; context.fillRect(0,0,side,side);
        """)
        fixture.load(script, token: token)
        try await waitForQuality(fixture, tokenId: token.id)
        let snapshot = try await fixture.snapshot()
        let canvas = try largestCanvas(snapshot)
        assertNativeResolution(canvas, snapshot: snapshot)
        XCTAssertEqual(number(canvas, "rectWidth") * Double(fixture.webView.pageZoom) * number(snapshot, "viewportScale"), 390, accuracy: 1)
        XCTAssertEqual(number(canvas, "rectHeight") * Double(fixture.webView.pageZoom) * number(snapshot, "viewportScale"), 390, accuracy: 1)
        XCTAssertGreaterThanOrEqual(number(canvas, "width") + 2, 390 * Double(fixture.nativeScale))
        let expectedDocuments = fixture.nativeScale > 1.02 ? 2 : 1
        try await assertStable(fixture, expectedDocuments: expectedDocuments)
        XCTAssertTrue(fixture.errors.isEmpty)
    }

    func testUnusedTemplateCanvasDoesNotOverrideTheDrawnSurfaceMeasurement() async throws {
        let fixture = try ResolutionFixture(size: CGSize(width: 390, height: 260))
        defer { fixture.close() }
        let (script, token) = try syntheticScript(source: """
        const template = document.body.appendChild(document.createElement('canvas'));
        template.id = 'unused-template'; template.width = 300; template.height = 150;
        template.style.width = '520px'; template.style.height = '260px';
        const canvas = document.body.appendChild(document.createElement('canvas'));
        canvas.id = 'drawn-artwork'; canvas.width = innerWidth; canvas.height = innerHeight;
        canvas.style.width = '100vw'; canvas.style.height = '100vh';
        const context = canvas.getContext('2d');
        context.fillStyle = '#237b43'; context.fillRect(0,0,canvas.width,canvas.height);
        """)
        fixture.load(script, token: token)
        try await waitForQuality(fixture, tokenId: token.id)
        let snapshot = try await fixture.snapshot()
        let canvases = try XCTUnwrap(snapshot["canvases"] as? [[String: Any]])
        let drawn = try XCTUnwrap(canvases.first { $0["id"] as? String == "drawn-artwork" })
        let template = try XCTUnwrap(canvases.first { $0["id"] as? String == "unused-template" })
        let quality = try XCTUnwrap(snapshot["quality"] as? [String: Any])
        assertNativeResolution(drawn, snapshot: snapshot)
        XCTAssertEqual(number(quality, "canvasWidth"), number(drawn, "width"))
        XCTAssertEqual(number(quality, "canvasHeight"), number(drawn, "height"))
        XCTAssertEqual(number(template, "width"), 300)
        XCTAssertEqual(number(template, "height"), 150)
        XCTAssertEqual(number(drawn, "x") * Double(fixture.webView.pageZoom) * number(snapshot, "viewportScale"), 0, accuracy: 1)
        XCTAssertEqual(number(drawn, "y") * Double(fixture.webView.pageZoom) * number(snapshot, "viewportScale"), 0, accuracy: 1)
        XCTAssertEqual(number(drawn, "rectWidth") * Double(fixture.webView.pageZoom) * number(snapshot, "viewportScale"), 390, accuracy: 1)
        XCTAssertEqual(number(drawn, "rectHeight") * Double(fixture.webView.pageZoom) * number(snapshot, "viewportScale"), 260, accuracy: 1)
        try await assertStable(fixture, expectedDocuments: fixture.nativeScale > 1.02 ? 2 : 1)
        XCTAssertTrue(fixture.errors.isEmpty)
    }

    func testFixedIntrinsicCanvasCannotGainQualityByShrinkingItsPresentation() async throws {
        let fixture = try ResolutionFixture()
        defer { fixture.close() }
        let (script, token) = try syntheticScript(source: """
        const canvas = document.body.appendChild(document.createElement('canvas'));
        canvas.width = canvas.height = 100;
        canvas.style.width = canvas.style.height = '100px';
        const context = canvas.getContext('2d');
        context.fillStyle = '#237b43'; context.fillRect(0,0,100,100);
        """)
        fixture.load(script, token: token)
        let expectedDocuments = fixture.nativeScale > 1.02 ? 3 : 1
        try await waitUntil { fixture.probe.documents.count == expectedDocuments && fixture.webView.pageZoom == 1 }
        try await assertStable(fixture, expectedDocuments: expectedDocuments)
        let canvas = try largestCanvas(try await fixture.snapshot())
        XCTAssertEqual(number(canvas, "width"), 100)
        XCTAssertEqual(number(canvas, "height"), 100)
        XCTAssertEqual(number(canvas, "rectWidth") * Double(fixture.webView.pageZoom), 100, accuracy: 0.5)
        XCTAssertEqual(number(canvas, "rectHeight") * Double(fixture.webView.pageZoom), 100, accuracy: 0.5)
        XCTAssertTrue(fixture.errors.isEmpty)
    }

    func testExistingDensityAwareCanvasKeepsItsOriginalDocumentAndZoom() async throws {
        let fixture = try ResolutionFixture()
        defer { fixture.close() }
        let (script, token) = try syntheticScript(source: canvasSource(densityAware: true))
        fixture.load(script, token: token)
        try await waitForQuality(fixture, tokenId: token.id)
        let snapshot = try await fixture.snapshot()
        assertNativeResolution(try largestCanvas(snapshot), snapshot: snapshot)
        XCTAssertEqual(fixture.webView.pageZoom, 1)
        try await assertStable(fixture, expectedDocuments: 1)
        XCTAssertTrue(fixture.errors.isEmpty)
    }

    func testPixelatedAndBlurredArtworkKeepTheirSampling() async throws {
        for style in ["image-rendering:pixelated", "filter:blur(2px)"] {
            let fixture = try ResolutionFixture()
            defer { fixture.close() }
            let (script, token) = try syntheticScript(source: canvasSource(densityAware: false, style: style))
            fixture.load(script, token: token)
            try await waitUntil { fixture.probe.documents.count == 1 }
            try await Task.sleep(for: .milliseconds(700))
            let snapshot = try await fixture.snapshot()
            XCTAssertTrue(snapshot["quality"] is NSNull)
            XCTAssertEqual(fixture.webView.pageZoom, 1)
            XCTAssertEqual(fixture.probe.documents.count, 1)
            let canvas = try largestCanvas(snapshot)
            if style.hasPrefix("filter") {
                XCTAssertTrue((canvas["filter"] as? String ?? "").contains("blur("))
            } else {
                XCTAssertEqual(canvas["imageRendering"] as? String, "pixelated")
            }
            XCTAssertTrue(fixture.errors.isEmpty)
        }
    }

    func testTemporarySamplingStylesFinishBeforeResolutionAdapts() async throws {
        for style in ["image-rendering:pixelated", "filter:blur(2px)"] {
            let fixture = try ResolutionFixture()
            defer { fixture.close() }
            let source = canvasSource(densityAware: false, style: style) + """
            setTimeout(() => { canvas.style.imageRendering = 'auto'; canvas.style.filter = ''; }, 750);
            """
            let (script, token) = try syntheticScript(source: source)
            fixture.load(script, token: token)
            try await waitUntil { fixture.probe.documents.count == 1 }
            try await Task.sleep(for: .milliseconds(350))
            XCTAssertEqual(fixture.webView.pageZoom, 1)
            try await waitForQuality(fixture, tokenId: token.id)
            let snapshot = try await fixture.snapshot()
            assertNativeResolution(try largestCanvas(snapshot), snapshot: snapshot)
            XCTAssertEqual(fixture.webView.pageZoom, 1 / fixture.nativeScale, accuracy: 0.02)
            XCTAssertEqual(fixture.probe.documents.count, fixture.nativeScale > 1.02 ? 2 : 1)
            XCTAssertTrue(fixture.errors.isEmpty)
        }
    }

    func testFixedUndersizedCanvasStopsRetryingAndRestoresOriginalZoom() async throws {
        let fixture = try ResolutionFixture()
        defer { fixture.close() }
        let (script, token) = try syntheticScript(source: canvasSource(densityAware: false, fixed: true))
        fixture.load(script, token: token)
        let expectedDocuments = fixture.nativeScale > 1.02 ? 3 : 1
        try await waitUntil { fixture.probe.documents.count == expectedDocuments && fixture.webView.pageZoom == 1 }
        try await assertStable(fixture, expectedDocuments: expectedDocuments)
        let canvas = try largestCanvas(try await fixture.snapshot())
        XCTAssertEqual(number(canvas, "width"), 100)
        XCTAssertEqual(number(canvas, "height"), 100)
        XCTAssertTrue(fixture.errors.isEmpty)
    }

    func testStaleTokenGenerationAndChildFrameReportsCannotChangeResolution() async throws {
        let fixture = try ResolutionFixture()
        defer { fixture.close() }
        let (script, token) = try syntheticScript(source: canvasSource(densityAware: true))
        fixture.load(script, token: token)
        try await waitForQuality(fixture, tokenId: token.id)
        let before = try await fixture.snapshot()
        let identity = try json(["collectionId": script.id, "tokenId": token.id])
        _ = try await fixture.webView.evaluateJavaScript("""
        (() => {
          const base = Object.assign(\(identity), { generation: window.__artBlocksPreviewGeneration,
            factor: 4, canvasWidth: 100, canvasHeight: 100, cssWidth: 300, cssHeight: 400 });
          webkit.messageHandlers.artBlocksPreviewResolution.postMessage(Object.assign({}, base, { generation: 'stale' }));
          webkit.messageHandlers.artBlocksPreviewResolution.postMessage(Object.assign({}, base, { tokenId: 'other-token' }));
          webkit.messageHandlers.artBlocksPreviewResolution.postMessage(Object.assign({}, base, { collectionId: 'other-collection' }));
          window.addEventListener('message', event => { if (event.data === 'child-resolution-sent') window.__childResolutionSent = true; });
          const frame = document.createElement('iframe');
          frame.style.display = 'none';
          frame.srcdoc = '<script>webkit.messageHandlers.artBlocksPreviewResolution.postMessage(' + JSON.stringify(base)
            + '); parent.postMessage("child-resolution-sent", "*");</' + 'script>';
          document.body.appendChild(frame);
          return true;
        })()
        """)
        try await waitUntil { (try? await fixture.webView.evaluateJavaScript("window.__childResolutionSent")) as? Bool == true }
        try await assertStable(fixture, expectedDocuments: 1)
        let after = try await fixture.snapshot()
        XCTAssertEqual(after["generation"] as? String, before["generation"] as? String)
        XCTAssertEqual(fixture.webView.pageZoom, 1)
        XCTAssertTrue(fixture.errors.isEmpty)
    }

    func testClearRemovesResolutionHandlerAndProductionViewsDoNotAdapt() async throws {
        let fixture = try ResolutionFixture()
        defer { fixture.close() }
        let (script, token) = try syntheticScript(source: canvasSource(densityAware: true))
        fixture.load(script, token: token)
        try await waitForQuality(fixture, tokenId: token.id)
        let identity = try json(["collectionId": script.id, "tokenId": token.id])
        _ = try await fixture.webView.evaluateJavaScript("""
        setTimeout(() => {
          const handler = window.webkit?.messageHandlers?.artBlocksPreviewResolution;
          if (handler) handler.postMessage(Object.assign(\(identity), {
            generation: window.__artBlocksPreviewGeneration,
            factor: 4, canvasWidth: 100, canvasHeight: 100, cssWidth: 300, cssHeight: 400 }));
          window.__lateResolutionFinished = true;
        }, 100); true;
        """)
        fixture.webView.clearArtBlocksRendering()
        try await waitUntil { (try? await fixture.webView.evaluateJavaScript("window.__lateResolutionFinished")) as? Bool == true }
        let handlerPresent = try await fixture.webView.evaluateJavaScript("Boolean(window.webkit?.messageHandlers?.artBlocksPreviewResolution)")
        XCTAssertEqual(handlerPresent as? Bool, false)
        XCTAssertEqual(fixture.webView.pageZoom, 1)
        try await assertStable(fixture, expectedDocuments: 1)

        let production = try ResolutionFixture(artBlocksRendering: false)
        defer { production.close() }
        let (productionScript, productionToken) = try syntheticScript(source: canvasSource(densityAware: false), artBlocksRendering: false)
        production.webView.pageZoom = 0.8
        production.webView.clearArtBlocksRendering()
        production.load(productionScript, token: productionToken, artBlocksRendering: false)
        try await waitUntil { production.probe.documents.count == 1 }
        try await Task.sleep(for: .milliseconds(700))
        XCTAssertEqual(production.webView.pageZoom, 0.8, accuracy: 0.001)
        XCTAssertEqual(production.probe.documents.count, 1)
        let productionReport = try await production.webView.evaluateJavaScript("typeof window.__artBlocksPreviewResolution")
        XCTAssertEqual(productionReport as? String, "undefined")
    }

    func testVaxtRendersWithNativeBackingResolution() async throws {
        try await verifyArtist("Växt")
    }

    func testVahriaKeepsRenderTargetsAndBothResolutionUniformsAligned() async throws {
        try await verifyArtist("Vahria")
    }

    func testAfterimageRendersWithNativeBackingResolution() async throws {
        try await verifyArtist("Afterimage")
    }

    func testLiquidRuminationsRendersWithNativeBackingResolution() async throws {
        try await verifyArtist("Liquid Ruminations")
    }

    func testAutopoiesisTilesRenderWithNativeBackingResolution() async throws {
        try await verifyArtist("Autopoiesis")
    }

    func testProcessingGenesisUsesRetinaPixelsWithoutChangingLogicalSize() async throws {
        try await verifyArtist("Genesis")
    }

    func testProcessingConstructionKeepsItsQuantizedGeometryAtRetinaDensity() async throws {
        try await verifyArtist("Construction Token")
    }

    private func verifyArtist(_ name: String, tokenIndex: Int = 0) async throws {
        let catalogURL = try XCTUnwrap(SuggestedItemsService.bundle.url(forResource: "items", withExtension: "json"))
        let catalog = try JSONDecoder().decode([SuggestedItem].self, from: Data(contentsOf: catalogURL))
        let item = try XCTUnwrap(catalog.first { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) == name })
        let scriptURL = try XCTUnwrap(JavaScriptLibraryFixtures.scriptURL(collectionId: item.id))
        let tokenURL = try XCTUnwrap(CollectionTokenFixtures.url(collectionId: item.id))
        let originalSource = try Data(contentsOf: scriptURL)
        let script = try XCTUnwrap(JavaScriptLibraryFixtures.script(collectionId: item.id))
        let tokens = try BundledTokens(data: Data(contentsOf: tokenURL)).items.resolvingAspectRatios(default: item.aspectRatio)
        let token = try XCTUnwrap(tokens.indices.contains(tokenIndex) ? tokens[tokenIndex] : nil)
        let ratio = try XCTUnwrap(token.aspectRatio)
        let fixture = try ResolutionFixture(size: CGSize(width: 300, height: 300 / ratio.value))
        defer { fixture.close() }
        fixture.load(script, token: token)
        try await waitForQuality(fixture, tokenId: token.id, timeout: 20)
        let completion: String?
        switch name {
        case "Bauhaus Synthesis": completion = "typeof frameCounter==='number' && frameCounter>=400 && p5.instance._loop===false"
        case "Can you see it": completion = "typeof hasDrawn!=='undefined' && hasDrawn===true"
        case "Time travel in a subconscious mind": completion = "typeof ST!=='undefined' && ST===3 && !!C1 && p5.instance._loop===false"
        case "Murano Fantasy": completion = "(()=>{const p=window.__resolutionInstances?.find(p=>p.canvas?.isConnected);return !!p&&p.frameCount>0&&p._loop===false;})()"
        default: completion = nil
        }
        if let completion {
            try await waitUntil(timeout: 120) { (try? await fixture.webView.evaluateJavaScript(completion)) as? Bool == true }
        }
        if name == "Time travel in a subconscious mind" {
            _ = try await fixture.webView.evaluateJavaScript("mousePressed(); null")
            try await waitUntil(timeout: 120) {
                (try? await fixture.webView.evaluateJavaScript("ST===1 && !!C2 && p5.instance._loop===false")) as? Bool == true
            }
            let rawCaches = try await fixture.webView.evaluateJavaScript("[C1,C2].map(c=>({width:c.width,height:c.height,bitmapWidth:c.canvas.width,bitmapHeight:c.canvas.height,density:c._pixelDensity}))")
            let caches = try XCTUnwrap(rawCaches as? [[String: Any]])
            for cache in caches {
                XCTAssertEqual(number(cache, "bitmapWidth"), number(cache, "width") * number(cache, "density"), accuracy: 1)
                XCTAssertGreaterThan(number(cache, "density"), 1)
            }
            _ = try await fixture.webView.evaluateJavaScript("mousePressed(); mousePressed(); null")
        }
        if name == "Murano Fantasy" {
            _ = try await fixture.webView.evaluateJavaScript("(()=>{const p=window.__resolutionInstances.find(p=>p.canvas?.isConnected);p.mouseX=p.width/2+.1*Math.min(p.width,p.height);p.mouseY=p.height/2;p.mouseClicked();p.mouseX=p.mouseY=-1;p.mouseClicked();return null;})()")
            let rawCopies = try await fixture.webView.evaluateJavaScript("window.__resolutionCopies")
            let copies = try XCTUnwrap(rawCopies as? [[String: Any]])
            XCTAssertTrue(copies.contains { number($0, "bitmapWidth") > number($0, "width") })
        }
        if name == "Bauhaus Synthesis" {
            let source = "img"
            let rawCache = try await fixture.webView.evaluateJavaScript("(()=>{const c=\(source);return {width:c.width,height:c.height,bitmapWidth:c.canvas.width,bitmapHeight:c.canvas.height,density:c._pixelDensity};})()")
            let cache = try XCTUnwrap(rawCache as? [String: Any])
            XCTAssertEqual(number(cache, "bitmapWidth"), number(cache, "width") * number(cache, "density"), accuracy: 1)
            XCTAssertGreaterThan(number(cache, "density"), 1)
        }
        try await Task.sleep(for: .milliseconds(500))
        let snapshot = try await fixture.snapshot()
        XCTAssertEqual(snapshot["tokenId"] as? String, token.id)
        XCTAssertEqual(snapshot["hash"] as? String, token.hash)
        XCTAssertEqual(try Data(contentsOf: scriptURL), originalSource)
        let surfaces = try displayedSurfaces(snapshot)
        XCTAssertFalse(surfaces.isEmpty)
        for canvas in surfaces { assertNativeResolution(canvas, snapshot: snapshot) }
        if name == "Liquid Ruminations" {
            let canvas = try largestCanvas(snapshot)
            let scale = Double(fixture.webView.pageZoom) * number(snapshot, "viewportScale")
            XCTAssertEqual(number(canvas, "x") * scale, 0, accuracy: 1)
            XCTAssertEqual(number(canvas, "y") * scale, 0, accuracy: 1)
            XCTAssertEqual(number(canvas, "rectWidth") * scale, Double(fixture.webView.bounds.width), accuracy: 1)
            XCTAssertEqual(number(canvas, "rectHeight") * scale, Double(fixture.webView.bounds.height), accuracy: 1)
        }
        if script.kind == .processingjs146 {
            XCTAssertEqual(fixture.webView.pageZoom, 1)
            for canvas in surfaces {
                XCTAssertEqual(number(canvas, "rectWidth"), number(canvas, "logicalWidth"), accuracy: 1)
                XCTAssertEqual(number(canvas, "rectHeight"), number(canvas, "logicalHeight"), accuracy: 1)
                XCTAssertEqual(number(canvas, "width"), number(canvas, "logicalWidth") * Double(fixture.nativeScale), accuracy: 1)
                XCTAssertEqual(number(canvas, "height"), number(canvas, "logicalHeight") * Double(fixture.nativeScale), accuracy: 1)
            }
        }
        let minimumZoom = 1 / fixture.nativeScale
        XCTAssertGreaterThanOrEqual(fixture.webView.pageZoom, minimumZoom - 0.001)
        XCTAssertLessThanOrEqual(fixture.webView.pageZoom, 1)
        if name == "Vahria" {
            let renderer = try XCTUnwrap(snapshot["vahria"] as? [String: Any])
            let buffer = try XCTUnwrap(renderer["buffer"] as? [Double])
            XCTAssertEqual(renderer["target"] as? [Double], buffer)
            XCTAssertEqual(renderer["ja"] as? [Double], buffer)
            XCTAssertEqual(renderer["passJa"] as? [Double], buffer)
        }
        XCTAssertTrue(fixture.errors.isEmpty, fixture.errors.joined(separator: "; "))
        let information: [String: Any] = ["artist": name, "nativeScale": fixture.nativeScale,
            "pageZoom": fixture.webView.pageZoom, "documents": fixture.probe.documents, "snapshot": snapshot]
        let metadata = XCTAttachment(data: try JSONSerialization.data(withJSONObject: information, options: [.prettyPrinted, .sortedKeys]), uniformTypeIdentifier: "public.json")
        metadata.name = "\(name) resolution"
        metadata.lifetime = .keepAlways
        add(metadata)
        let image = try await fixture.webView.takeSnapshot(configuration: nil)
        let attachment = XCTAttachment(image: image)
        attachment.name = "\(name) native artwork"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func syntheticScript(source: String, artBlocksRendering: Bool = true) throws -> (Script, BundledTokens.Item) {
        let id = "resolution-test-\(UUID().uuidString)"
        let script = Script(
            id: id, address: "0xresolution", name: "Resolution fixture", abId: "0", value: source,
            metadata: .init(kind: .js, renderingProfile: artBlocksRendering ? .artBlocks : nil, requiresInitialCanvas: false)
        )
        let token = BundledTokens.Item(id: "17", name: nil, hash: "0x" + String(repeating: "a", count: 64))
        return (script, token)
    }

    private func canvasSource(densityAware: Bool, style: String = "", fixed: Bool = false) -> String {
        """
        const canvas = document.body.appendChild(document.createElement('canvas'));
        canvas.width = \(fixed ? "100" : "Math.round(innerWidth * \(densityAware ? "devicePixelRatio" : "1"))");
        canvas.height = \(fixed ? "100" : "Math.round(innerHeight * \(densityAware ? "devicePixelRatio" : "1"))");
        canvas.style.cssText = 'width:100vw;height:100vh;\(style)';
        const context = canvas.getContext('2d');
        context.fillStyle = '#237b43'; context.fillRect(0,0,canvas.width,canvas.height);
        """
    }

    private func waitForQuality(_ fixture: ResolutionFixture, tokenId: String, timeout: TimeInterval = 8) async throws {
        do {
            try await waitUntil(timeout: timeout) {
                guard let snapshot = try? await fixture.snapshot(), snapshot["tokenId"] as? String == tokenId,
                      let generation = snapshot["generation"] as? String,
                      fixture.probe.documents.last?["generation"] as? String == generation,
                      let quality = snapshot["quality"] as? [String: Any],
                      let factor = quality["factor"] as? Double else { return false }
                return factor <= 1.02
            }
        } catch {
            if let snapshot = try? await fixture.snapshot(), let details = try? json(snapshot) {
                print("RESOLUTION_FAILURE zoom=\(fixture.webView.pageZoom) documents=\(fixture.probe.documents.count) \(details)")
            }
            throw error
        }
    }

    private func assertStable(_ fixture: ResolutionFixture, expectedDocuments: Int) async throws {
        let before = try await fixture.snapshot()
        let generation = before["generation"] as? String
        try await Task.sleep(for: .milliseconds(700))
        XCTAssertEqual(fixture.probe.documents.count, expectedDocuments)
        let after = try await fixture.snapshot()
        XCTAssertEqual(after["generation"] as? String, generation)
    }

    private func displayedSurfaces(_ snapshot: [String: Any]) throws -> [[String: Any]] {
        let width = number(snapshot, "width"), height = number(snapshot, "height")
        let canvases = try XCTUnwrap(snapshot["canvases"] as? [[String: Any]]).filter {
            number($0, "rectWidth") > 0 && number($0, "rectHeight") > 0 && $0["display"] as? String != "none"
                && number($0, "x") < width && number($0, "y") < height
                && number($0, "x") + number($0, "rectWidth") > 0 && number($0, "y") + number($0, "rectHeight") > 0
        }
        let largest = canvases.map { number($0, "rectWidth") * number($0, "rectHeight") }.max() ?? 0
        let threshold = largest >= width * height * 0.5 ? largest * 0.95 : largest * 0.25
        return canvases.filter { number($0, "rectWidth") * number($0, "rectHeight") >= threshold }
    }

    private func largestCanvas(_ snapshot: [String: Any]) throws -> [String: Any] {
        try XCTUnwrap(displayedSurfaces(snapshot).max { number($0, "rectWidth") * number($0, "rectHeight") < number($1, "rectWidth") * number($1, "rectHeight") })
    }

    private func assertNativeResolution(_ canvas: [String: Any], snapshot: [String: Any]) {
        let density = max(0.01, number(snapshot, "dpr") * number(snapshot, "viewportScale"))
        XCTAssertGreaterThanOrEqual(number(canvas, "width") + 2, number(canvas, "rectWidth") * density)
        XCTAssertGreaterThanOrEqual(number(canvas, "height") + 2, number(canvas, "rectHeight") * density)
    }

    private func number(_ object: [String: Any], _ key: String) -> Double {
        (object[key] as? NSNumber)?.doubleValue ?? 0
    }

    private func json(_ object: Any) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }

    private func waitUntil(timeout: TimeInterval = 8, _ predicate: @escaping @MainActor () async -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await predicate() { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTFail("Timed out waiting for stable artwork resolution")
        throw CancellationError()
    }
}
