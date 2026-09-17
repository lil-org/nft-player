import CryptoKit
import Foundation
import UIKit
import WebKit
import XCTest
@testable import nft_player_ios

nonisolated final class ArtBlocksRenderingTests: XCTestCase {}

@MainActor
private final class FinalReviewOperation<Value: Sendable> {
    private var completion: ((Result<Value, Error>) -> Void)?
    var timeoutTask: Task<Void, Never>?

    init(_ completion: @escaping (Result<Value, Error>) -> Void) {
        self.completion = completion
    }

    func finish(_ result: Result<Value, Error>) {
        guard let completion else { return }
        self.completion = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        completion(result)
    }
}

@MainActor
private final class FinalReviewDocumentProbe: NSObject, WKScriptMessageHandler {
    var documents: [[String: Any]] = []

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let body = message.body as? [String: Any],
              let generation = body["generation"] as? String,
              !documents.contains(where: { $0["generation"] as? String == generation }) else { return }
        documents.append(body)
    }
}

@MainActor
private final class RenderingFixture {
    let webView = AutoReloadingWebView.newArtBlocksRenderer()
    let probe = FinalReviewDocumentProbe()
    let window: UIWindow
    var errors: [String] = []
    private(set) var loadedHTML = ""

    init(size: CGSize) throws {
        webView.artworkDependencyCache = JavaScriptLibraryFixtures.cache
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        webView.frame = CGRect(origin: .zero, size: size)
        webView.configuration.userContentController.add(probe, name: "finalReviewDocumentProbe")
        webView.configuration.userContentController.addUserScript(WKUserScript(source: Self.probeSource,
            injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let host = UIViewController()
        host.view.addSubview(webView)
        window = UIWindow(windowScene: scene)
        window.rootViewController = host
        window.isHidden = false
        window.layoutIfNeeded()
    }

    func load(script: Script, token: BundledTokens.Item, size: CGSize, html suppliedHTML: String? = nil) {
        errors = []
        webView.invalidateRequestedContent()
        webView.configureArtBlocksRendering(collectionId: script.id, tokenId: token.id) { [weak self] in
            self?.errors.append($0)
        }
        webView.frame.size = size
        var html = suppliedHTML ?? RawHtmlGenerator.createHtml(script: script, token: token)
        if let start = html.range(of: "<script>let tokenData = "),
           let end = html[start.upperBound...].range(of: "</script>") {
            html.insert(contentsOf: "window.__finalReviewOriginalToken={tokenId:tokenData.tokenId,hash:tokenData.hash||tokenData.hashes?.[0]};", at: end.lowerBound)
        }
        let name = String(data: try! JSONSerialization.data(withJSONObject: script.name, options: [.fragmentsAllowed]), encoding: .utf8)!
        if let head = html.range(of: "<head>") {
            html.insert(contentsOf: "<script>window.__finalReviewArtistName=\(name);</script>", at: head.upperBound)
        }
        loadedHTML = html
        webView.loadHTMLString(html, baseURL: nil)
    }

    func close() {
        webView.stopLoading()
        webView.unloadContent()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "finalReviewDocumentProbe")
        window.isHidden = true
        window.rootViewController = nil
    }

    func evaluate(_ source: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let operation = FinalReviewOperation<String> { continuation.resume(with: $0) }
            webView.evaluateJavaScript(source) { value, error in
                if let error { operation.finish(.failure(error)) }
                else if let value = value as? String { operation.finish(.success(value)) }
                else { operation.finish(.failure(NSError(domain: "FinalReviewMissingEvaluation", code: 1))) }
            }
            operation.timeoutTask = Task { @MainActor in
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
                operation.finish(.failure(NSError(domain: "FinalReviewEvaluationTimeout", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Artwork JavaScript did not respond within five seconds"])))
            }
        }
    }

    func screenshot() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let operation = FinalReviewOperation<Data> { continuation.resume(with: $0) }
            webView.takeSnapshot(with: nil) { image, error in
                if let error { operation.finish(.failure(error)) }
                else if let data = image?.pngData() { operation.finish(.success(data)) }
                else { operation.finish(.failure(NSError(domain: "FinalReviewMissingSnapshot", code: 1))) }
            }
            operation.timeoutTask = Task { @MainActor in
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
                operation.finish(.failure(NSError(domain: "FinalReviewSnapshotTimeout", code: 1)))
            }
        }
    }

    func snapshot() async throws -> [String: Any] {
        let result = try await evaluate("JSON.stringify(window.__finalReviewSnapshot ? window.__finalReviewSnapshot() : {ready:false})")
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(result.utf8)) as? [String: Any])
    }

    private static let probeSource = """
    (function () {
      const drawn = new WeakSet(), contexts = new WeakSet();
      const bitmapWidth = Object.getOwnPropertyDescriptor(HTMLCanvasElement.prototype, 'width').get;
      const bitmapHeight = Object.getOwnPropertyDescriptor(HTMLCanvasElement.prototype, 'height').get;
      const getContext = HTMLCanvasElement.prototype.getContext;
      let firstDrawAt = null;
      HTMLCanvasElement.prototype.getContext = function () {
        const context = getContext.apply(this, arguments), canvas = this;
        if (!context || contexts.has(context)) return context;
        contexts.add(context);
        const methods = arguments[0] === '2d'
          ? ['fill','stroke','fillRect','strokeRect','drawImage','putImageData','fillText','strokeText']
          : ['drawArrays','drawElements','drawArraysInstanced','drawElementsInstanced'];
        const originals = new Map();
        methods.forEach(function (name) {
          const original = context[name], descriptor = Object.getOwnPropertyDescriptor(context,name);
          if (typeof original !== 'function') return;
          const wrapper = function () {
            const result = original.apply(this, arguments);
            drawn.add(canvas);
            if (firstDrawAt === null) firstDrawAt = performance.now();
            originals.forEach(function (entry, method) {
              if (context[method] !== entry.wrapper) return;
              if (entry.descriptor) Object.defineProperty(context,method,entry.descriptor); else delete context[method];
            });
            originals.clear();
            return result;
          };
          try {
            Object.defineProperty(context,name,{configurable:true,writable:true,value:wrapper});
            originals.set(name,{descriptor:descriptor,wrapper:wrapper});
          } catch (_) {}
        });
        return context;
      };
      function visible(element) {
        const r=element.getBoundingClientRect();
        if (!(r.width>0 && r.height>0 && r.right>0 && r.bottom>0 && r.left<innerWidth && r.top<innerHeight)) return false;
        for (let node=element;node;node=node.parentElement) {
          const s=getComputedStyle(node);
          if (s.display==='none'||s.visibility==='hidden'||Number(s.opacity)===0) return false;
        }
        return true;
      }
      function rect(element) {
        if (!element) return null;
        const r=element.getBoundingClientRect();
        return {x:r.x,y:r.y,width:r.width,height:r.height,scrollWidth:element.scrollWidth,scrollHeight:element.scrollHeight};
      }
      window.__finalReviewSnapshot=function () {
        const identity=window.__finalReviewOriginalToken || (typeof tokenData==='object'&&tokenData?tokenData:{});
        const canvases=[...document.querySelectorAll('canvas')].map((canvas,index)=>({
          index:index,id:canvas.id,width:bitmapWidth.call(canvas),height:bitmapHeight.call(canvas),
          rect:rect(canvas),visible:visible(canvas),drawn:drawn.has(canvas)
        }));
        const svgs=[...document.querySelectorAll('svg')].filter(e=>visible(e)&&e.querySelectorAll('*').length>1);
        const media=[...document.querySelectorAll('img,video')].filter(e=>visible(e)
          &&(e.tagName==='IMG'?e.complete&&e.naturalWidth>0:e.readyState>=2&&e.videoWidth>0));
        let ready=canvases.some(c=>c.visible&&c.drawn)||svgs.length>0||media.length>0;
        let basis=canvases.some(c=>c.visible&&c.drawn)?'observed-drawing':svgs.length?'visible-svg':media.length?'decoded-media':'waiting';
        if (window.__finalReviewArtistName==='Breathe You') {
          const count=parseInt(identity.hash.slice(34,36),16)+256;
          ready=!!document.getElementById('sktch')&&document.querySelectorAll('[id^=circle-block]').length===count
            &&!!document.getElementById('pupil'+(count-1));basis='artist-dom';
        }
        if (window.__finalReviewArtistName==='striation') {
          const grid=document.getElementById('gridContainer');
          ready=typeof numberOfDivs==='number'&&numberOfDivs>0&&grid?.children.length===numberOfDivs
            &&!!document.getElementById('square_'+(numberOfDivs-1));basis='artist-dom';
        }
        const loader=document.getElementById('loading-overlay');
        if (loader&&visible(loader)) ready=false;
        return {ready:ready,basis:basis,generation:window.__artBlocksPreviewGeneration||null,
          tokenId:identity.tokenId||null,hash:identity.hash||identity.hashes?.[0]||null,
          readyState:document.readyState,timestamp:performance.now(),firstDrawAt:firstDrawAt,
          width:innerWidth,height:innerHeight,dpr:devicePixelRatio,viewportScale:window.visualViewport?.scale||1,
          body:rect(document.body),document:rect(document.documentElement),canvases:canvases,
          svgs:svgs.map(rect),media:media.map(e=>({tag:e.tagName,rect:rect(e)})),
          interactionRequested:window.__finalReviewInteractionRequested||null,
          quality:window.__artBlocksPreviewResolution||null};
      };
      document.addEventListener('DOMContentLoaded',function () {
        const identity=window.__finalReviewOriginalToken || (typeof tokenData==='object'&&tokenData?tokenData:{});
        window.webkit.messageHandlers.finalReviewDocumentProbe.postMessage({
          generation:window.__artBlocksPreviewGeneration,tokenId:identity.tokenId||null,
          hash:identity.hash||identity.hashes?.[0]||null,width:innerWidth,height:innerHeight,timestamp:performance.now()
        });
        if (window.__finalReviewArtistName==='Inhabitants') setTimeout(function () {
          if (typeof document.onclick!=='function') return;
          window.__finalReviewInteractionRequested={kind:'artist-document-click',timestamp:performance.now()};
          document.onclick(new MouseEvent('click'));
        },0);
      },{once:true});
    }());
    """
}

@MainActor
extension ArtBlocksRenderingTests {
    private struct Resources {
        let script: Script
        let tokens: [BundledTokens.Item]
        let scriptURL: URL
        let tokensURL: URL
        let source: Data
        let tokenData: Data
    }

    func testRenderingRepresentativeTiming() async throws {
        try await benchmark(useBaseline: false)
    }

    func testRenderingBaselineTiming() async throws {
        let baseline = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("build/artblocks-promotion/before/html")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: baseline.path), "Requires the captured pre-pass timing baseline")
        try await benchmark(useBaseline: true)
    }

    func testAutopoiesisStartsAtFullQualityWithoutCorrectiveReload() async throws {
        let id = "0x47a91457a3a1f700097199fd63c039c4784384ab80"
        let resources = try resources(id)
        let token = try XCTUnwrap(resources.tokens.first)
        let viewport = try size(for: token)
        let baselineURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("build/artblocks-promotion/before/html/\(id).html")
        let modes = FileManager.default.fileExists(atPath: baselineURL.path) ? [true,false] : [false]
        for baseline in modes {
            let html = baseline ? try String(contentsOf: baselineURL, encoding: .utf8) : nil
            let fixture = try RenderingFixture(size: viewport)
            defer { fixture.close() }
            AutoReloadingWebView.resetStartupCalibrationsForTesting()
            let started = Date()
            fixture.load(script: resources.script, token: token, size: viewport, html: html)
            _ = try await waitForAppearance(fixture, script: resources.script, token: token, after: 0, started: started)
            var snapshot = try await fixture.snapshot()
            while Date().timeIntervalSince(started) < 20 {
                if let quality = snapshot["quality"] as? [String: Any], let factor = quality["factor"] as? Double, factor <= 1.02 { break }
                try await Task.sleep(for: .milliseconds(10))
                snapshot = try await fixture.snapshot()
            }
            let quality = try XCTUnwrap(snapshot["quality"] as? [String: Any])
            XCTAssertLessThanOrEqual(try XCTUnwrap(quality["factor"] as? Double), 1.02)
            if !baseline { XCTAssertEqual(fixture.probe.documents.count, 1) }
            let result: [String: Any] = ["baseline":baseline,"milliseconds":Date().timeIntervalSince(started)*1000,
                "documents":fixture.probe.documents.count,"snapshot":snapshot]
            print("AUTOPOIESIS_STABLE_JSON \(String(decoding: try JSONSerialization.data(withJSONObject: result,options:[.sortedKeys]),as:UTF8.self))")
            attachJSON(result,name:"Autopoiesis \(baseline ? "before" : "after") stable quality")
        }
    }

    private func benchmark(useBaseline: Bool) async throws {
        let representatives = [
            ("Breathe You", "0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd27075"),
            ("striation", "0x47a91457a3a1f700097199fd63c039c4784384ab75"),
            ("Hypertype", "0xbb5471c292065d3b01b2e81e299267221ae9a2500"),
            ("Genesis", "0x059edd72cd353df5106d2b9cc5ab83a52287ac3a1"),
            ("Afterimage", "0x47a91457a3a1f700097199fd63c039c4784384ab3"),
            ("Autopoiesis", "0x47a91457a3a1f700097199fd63c039c4784384ab80"),
            ("Aragnation", "0x99a9b7c1116f9ceeb1652de04d5969cce509b069401"),
            ("100 Sunsets", "0x0a1bbd57033f57e7b6743621b79fcb9eb2ce367629"),
            ("Gift of Time", "0x000000dc68934ed27fd11e32491cdf6717acaf211"),
            ("Classical Revival", "0x000000098a14b4e08132fd55faec521ab597a0010")
        ]
        for (name, id) in representatives {
            let resources = try resources(id)
            let token = try XCTUnwrap(resources.tokens.first)
            let size = try size(for: token)
            let baselineURL = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("build/artblocks-promotion/before/html/\(id).html")
            let benchmarkHTML = useBaseline
                ? try String(contentsOf: baselineURL, encoding: .utf8)
                : RawHtmlGenerator.createHtml(script: resources.script, token: token)
            for repeatIndex in 1...2 {
                AutoReloadingWebView.resetStartupCalibrationsForTesting()
                let fixture = try RenderingFixture(size: size)
                defer { fixture.close() }
                for phase in ["fresh", "reuse"] {
                    let previousDocuments = fixture.probe.documents.count
                    let started = Date()
                    fixture.load(script: resources.script, token: token, size: size, html: benchmarkHTML)
                    let first = try await waitForAppearance(fixture, script: resources.script, token: token,
                        after: previousDocuments, started: started)
                    let result: [String: Any] = [
                        "name": name, "collectionId": id, "tokenId": token.id, "repeat": repeatIndex,
                        "phase": phase, "baselineHTML": useBaseline, "milliseconds": Date().timeIntervalSince(started) * 1000,
                        "profile": fixture.webView.usesStableArtworkPresentation,
                        "documents": fixture.probe.documents.count - previousDocuments,
                        "pageZoom": Double(fixture.webView.pageZoom), "screenScale": Double(fixture.window.screen.scale),
                        "readiness": first, "errors": fixture.errors
                    ]
                    print("FINAL_REVIEW_LATENCY_JSON \(String(decoding: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), as: UTF8.self))")
                    attachJSON(result, name: "\(name) \(repeatIndex) \(phase) first appearance latency")
                    fixture.webView.invalidateRequestedContent()
                }
            }
            XCTAssertEqual(try Data(contentsOf: resources.scriptURL), resources.source)
            XCTAssertEqual(try Data(contentsOf: resources.tokensURL), resources.tokenData)
        }
    }

    func testRendering001Logoria() async throws { try await verifyCollection("0x00009f857c1ccd5ca0dc5900427fb8da006280991", name: " Logoria") }
    func testRendering002Classifieds() async throws { try await verifyCollection("0x32d4be5ee74376e08038d652d4dc26e62c67f43619", name: "[classifieds]") }
    func testRendering003PostKonstrukt() async throws { try await verifyCollection("0x62e37f664b5945629b6549a87f8e10ed0b6d923b1", name: "[post]-konstrukt") }
    func testRendering004MICRO1() async throws { try await verifyCollection("0x0000000080d04343d60d06e1a36aaf46c92428053", name: "{MICRO¹}") }
    func testRendering0058() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270179", name: "8") }
    func testRendering00670sPopSeriesOne() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd27046", name: "70s Pop Series One") }
    func testRendering00770sPopSeriesTwo() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd27085", name: "70s Pop Series Two") }
    func testRendering008100Sunsets() async throws { try await verifyCollection("0x0a1bbd57033f57e7b6743621b79fcb9eb2ce367629", name: "100 Sunsets") }
    func testRendering009720Minutes() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd27027", name: "720 Minutes") }
    func testRendering010ATemporaryArrangementOfMaterial() async throws { try await verifyCollection("0x0a1bbd57033f57e7b6743621b79fcb9eb2ce367677", name: "a temporary arrangement of material") }
    func testRendering011Aceleraciones() async throws { try await verifyCollection("0x47a91457a3a1f700097199fd63c039c4784384ab43", name: "Aceleraciones") }
    func testRendering012Afterimage() async throws { try await verifyCollection("0x47a91457a3a1f700097199fd63c039c4784384ab3", name: "Afterimage") }
    func testRendering013Aitherios() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270196", name: "Aithérios") }
    func testRendering014Alchimie() async throws { try await verifyCollection("0x000000a6e6366baf7c98a2ab73d3df1092dd7bb00", name: "Alchimie") }
    func testRendering015Aleph0() async throws { try await verifyCollection("0xf03511ec774289da497cdb2070df4c711580ff7a0", name: "Aleph-0") }
    func testRendering016AlienDNA() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270294", name: "Alien DNA") }
    func testRendering017AllOurFaces() async throws { try await verifyCollection("0x47a91457a3a1f700097199fd63c039c4784384ab7", name: "All Our Faces") }
    func testRendering018AllTheTime() async throws { try await verifyCollection("0x68c01cb4733a82a58d5e7bb31bddbff26a3a35d523", name: "All The Time") }
    func testRendering019AncientCoursesOfFictionalRivers() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270284", name: "Ancient Courses of Fictional Rivers") }
    func testRendering020AndYetWeLove() async throws { try await verifyCollection("0x47a91457a3a1f700097199fd63c039c4784384ab290", name: "And Yet We Love") }
    func testRendering021Andradite() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd27071", name: "Andradite") }
    func testRendering022Anticyclone() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270304", name: "Anticyclone") }
    func testRendering023Aodach() async throws { try await verifyCollection("0x47a91457a3a1f700097199fd63c039c4784384ab92", name: "Aodach") }
    func testRendering024Apophenies() async throws { try await verifyCollection("0x0a1bbd57033f57e7b6743621b79fcb9eb2ce367661", name: "Apophenies") }
    func testRendering025Aragnation() async throws { try await verifyCollection("0x99a9b7c1116f9ceeb1652de04d5969cce509b069401", name: "Aragnation") }
    func testRendering026Asemica() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270206", name: "Asemica") }
    func testRendering027Assembly() async throws { try await verifyCollection("0x99a9b7c1116f9ceeb1652de04d5969cce509b069445", name: "Assembly") }
    func testRendering028AssortedPositivity() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270319", name: "Assorted Positivity") }
    func testRendering029Asterisms() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd27047", name: "Asterisms") }
    func testRendering030Atlas() async throws { try await verifyCollection("0xaf40b66072fe00cacf5a25cd1b7f1688cde20f2f2", name: "Atlas") }
    func testRendering031Attraction() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270229", name: "Attraction") }
    func testRendering032Autology() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270209", name: "Autology") }
    func testRendering033Automatism() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270281", name: "Automatism") }
    func testRendering034Autopoiesis() async throws { try await verifyCollection("0x47a91457a3a1f700097199fd63c039c4784384ab80", name: "Autopoiesis ") }
    func testRendering035Balance() async throws { try await verifyCollection("0x68c01cb4733a82a58d5e7bb31bddbff26a3a35d533", name: "Balance") }
    func testRendering036Balance() async throws { try await verifyCollection("0x99a9b7c1116f9ceeb1652de04d5969cce509b069489", name: "Balance") }
    func testRendering037Balletic() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270343", name: "Balletic") }
    func testRendering038BauhausSynthesis() async throws { try await verifyCollection("0x47a91457a3a1f700097199fd63c039c4784384ab278", name: "Bauhaus Synthesis") }
    func testRendering039BeautyInTheHurting() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270178", name: "Beauty in the Hurting") }
    func testRendering040BeingYourselfWhileFittingIn() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270342", name: "Being Yourself While Fitting In") }
    func testRendering041Bent() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270214", name: "Bent") }
    func testRendering042BlaschkeBallet() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270167", name: "Blaschke Ballet") }
    func testRendering043BlockbobRorschach() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270188", name: "Blockbob Rorschach") }
    func testRendering044Box() async throws { try await verifyCollection("0x68c01cb4733a82a58d5e7bb31bddbff26a3a35d538", name: "Box") }
    func testRendering045BoxLightStudies() async throws { try await verifyCollection("0xab0000000000aa06f89b268d604a9c1c41524ac6499", name: "Box Light Studies") }
    func testRendering046Brava() async throws { try await verifyCollection("0x0a1bbd57033f57e7b6743621b79fcb9eb2ce367680", name: "Brava") }
    func testRendering047BreatheYou() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd27075", name: "Breathe You") }
    func testRendering048Brickwork() async throws { try await verifyCollection("0xa319c382a702682129fcbf55d514e61a16f97f9c7", name: "Brickwork") }
    func testRendering049Bright() async throws { try await verifyCollection("0x99a9b7c1116f9ceeb1652de04d5969cce509b069448", name: "Bright") }
    func testRendering050BubbleBlobby() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd27062", name: "Bubble Blobby") }
    func testRendering051Calendart() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270125", name: "Calendart") }
    func testRendering052Calian() async throws { try await verifyCollection("0x99a9b7c1116f9ceeb1652de04d5969cce509b069416", name: "Calian") }
    func testRendering053Caminos() async throws { try await verifyCollection("0x0a1bbd57033f57e7b6743621b79fcb9eb2ce367631", name: "Caminos") }
    func testRendering054CanYouSeeIt() async throws { try await verifyCollection("0x47a91457a3a1f700097199fd63c039c4784384ab315", name: "Can you see it") }
    func testRendering055Carattere() async throws { try await verifyCollection("0x9800005deb3cfaf80077dbe9b9004c0020c1d6c50", name: "Carattere") }
    func testRendering056CathedralStudy() async throws { try await verifyCollection("0x1353fd9d3dc70d1a18149c8fb2adb4fb906de4e86", name: "cathedral study") }
    func testRendering057Cells() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270122", name: "Cells") }
    func testRendering058Cerebellum() async throws { try await verifyCollection("0x99a9b7c1116f9ceeb1652de04d5969cce509b069412", name: "Cerebellum") }
    func testRendering059ChromaGenesis() async throws { try await verifyCollection("0xb3526a6400260078517643cfd8490078803e00000", name: "Chroma Genesis") }
    func testRendering060ChromaTheory() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270170", name: "Chroma Theory") }
    func testRendering061Chronicles() async throws { try await verifyCollection("0x32d4be5ee74376e08038d652d4dc26e62c67f43611", name: "Chronicles") }
    func testRendering062Circulate() async throws { try await verifyCollection("0x68c01cb4733a82a58d5e7bb31bddbff26a3a35d531", name: "Circulate") }
    func testRendering063CityZen() async throws { try await verifyCollection("0x47a91457a3a1f700097199fd63c039c4784384ab275", name: "CityZen") }
    func testRendering064ClassicalRevival() async throws { try await verifyCollection("0x000000098a14b4e08132fd55faec521ab597a0010", name: "Classical Revival") }
    func testRendering065Cohesion() async throws { try await verifyCollection("0x47a91457a3a1f700097199fd63c039c4784384ab17", name: "Cohesion") }
    func testRendering066ColorStudy() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd27016", name: "Color Study") }
    func testRendering067ComplexCity20002023() async throws { try await verifyCollection("0x5fdf5e6caf7b8b0f64c3612afd85e9407a7e13891", name: "ComplexCity (2000/2023)") }
    func testRendering068ConstructionToken() async throws { try await verifyCollection("0x059edd72cd353df5106d2b9cc5ab83a52287ac3a2", name: "Construction Token") }
    func testRendering069Contours() async throws { try await verifyCollection("0x000000058b5d9e705ee989fabc8dfdc1bfbdfa6b1", name: "Contours") }
    func testRendering070Corners() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270292", name: "Corners") }
    func testRendering071CreativeChaos() async throws { try await verifyCollection("0x47a91457a3a1f700097199fd63c039c4784384ab186", name: "Creative Chaos") }
    func testRendering072Cuadro() async throws { try await verifyCollection("0x0a1bbd57033f57e7b6743621b79fcb9eb2ce367663", name: "Cuadro") }
    func testRendering073Culmination() async throws { try await verifyCollection("0x0a1bbd57033f57e7b6743621b79fcb9eb2ce367684", name: "Culmination") }
    func testRendering074Cushions() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270231", name: "Cushions") }
    func testRendering075CyberCities() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd27014", name: "Cyber Cities") }
    func testRendering076DearHash() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd27049", name: "Dear Hash,") }
    func testRendering077DeconstructedCityPlans() async throws { try await verifyCollection("0xd10e3dee203579fcee90ed7d0bdd8086f7e53beb1", name: "Deconstructed City Plans") }
    func testRendering078Decores() async throws { try await verifyCollection("0x32d4be5ee74376e08038d652d4dc26e62c67f4366", name: "Décorés") }
    func testRendering079Degenerative() async throws { try await verifyCollection("0xcfa6a2d5bc2a77c0cdd3046e09da21e45d1df0f11", name: "degenerative") }
    func testRendering080DejaVu() async throws { try await verifyCollection("0x1353fd9d3dc70d1a18149c8fb2adb4fb906de4e87", name: "Deja Vu") }
    func testRendering081Delights() async throws { try await verifyCollection("0x47a91457a3a1f700097199fd63c039c4784384ab82", name: "Delights") }
    func testRendering082Descent() async throws { try await verifyCollection("0x0a1bbd57033f57e7b6743621b79fcb9eb2ce367674", name: "Descent") }
    func testRendering083DigitalSketch() async throws { try await verifyCollection("0x000009bb1740eea484f7db00000a9227e578bf965", name: "Digital Sketch") }
    func testRendering084Directions() async throws { try await verifyCollection("0x68c01cb4733a82a58d5e7bb31bddbff26a3a35d511", name: "Directions") }
    func testRendering085Downtown() async throws { try await verifyCollection("0x47a91457a3a1f700097199fd63c039c4784384ab30", name: "Downtown ") }
    func testRendering086Dreams() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd27089", name: "Dreams") }
    func testRendering087DynamicSlices() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd2704", name: "Dynamic Slices") }
    func testRendering088EPASTELII() async throws { try await verifyCollection("0x0000001590abfb45b052c28fb7dac11c062b93370", name: "E-PASTEL II") }
    func testRendering089Eccentrics() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270104", name: "Eccentrics") }
    func testRendering090Eccentrics2Orbits() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270139", name: "Eccentrics 2: Orbits") }
    func testRendering091EchoesOfFridaSutura() async throws { try await verifyCollection("0x0000000fae63d15270aafe9e08a71cd28079572d1", name: "Echoes Of Frida: Sutura") }
    func testRendering092Enchiridion() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270101", name: "Enchiridion") }
    func testRendering093Encore() async throws { try await verifyCollection("0x0a1bbd57033f57e7b6743621b79fcb9eb2ce367682", name: "Encore") }
    func testRendering094Ensemble() async throws { try await verifyCollection("0xd10e3dee203579fcee90ed7d0bdd8086f7e53beb0", name: "Ensemble") }
    func testRendering095Entretiempos() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270267", name: "entretiempos") }
    func testRendering096Erratic() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270362", name: "Erratic") }
    func testRendering097FakeInternetMoney() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270152", name: "Fake Internet Money") }
    func testRendering098FermentedFruit() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270321", name: "Fermented Fruit") }
    func testRendering099FieldImpact() async throws { try await verifyCollection("0x000000a6e6366baf7c98a2ab73d3df1092dd7bb01", name: "Field Impact") }
    func testRendering100Flood() async throws { try await verifyCollection("0x68c01cb4733a82a58d5e7bb31bddbff26a3a35d53", name: "Flood") }
    func testRendering101Flowers() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270116", name: "Flowers") }
    func testRendering102Fluiroso() async throws { try await verifyCollection("0x99a9b7c1116f9ceeb1652de04d5969cce509b069473", name: "Fluiroso") }
    func testRendering103Fold() async throws { try await verifyCollection("0x68c01cb4733a82a58d5e7bb31bddbff26a3a35d57", name: "Fold") }
    func testRendering104Fold() async throws { try await verifyCollection("0xaf40b66072fe00cacf5a25cd1b7f1688cde20f2f1", name: "Fold") }
    func testRendering105Forecast() async throws { try await verifyCollection("0x99a9b7c1116f9ceeb1652de04d5969cce509b069470", name: "Forecast") }
    func testRendering106Formation() async throws { try await verifyCollection("0x0a1bbd57033f57e7b6743621b79fcb9eb2ce367611", name: "Formation") }
    func testRendering107FriendshipBracelets() async throws { try await verifyCollection("0x942bc2d3e7a589fe5bd4a5c6ef9727dfd82f5c8a0", name: "Friendship Bracelets") }
    func testRendering108FULLSPECTRUM() async throws { try await verifyCollection("0x0a1bbd57033f57e7b6743621b79fcb9eb2ce367646", name: "FULL_SPECTRUM") }
    func testRendering109Gazers() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270215", name: "Gazers") }
    func testRendering110Genesis() async throws { try await verifyCollection("0x059edd72cd353df5106d2b9cc5ab83a52287ac3a1", name: "Genesis") }
    func testRendering111GeometryRunners() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270138", name: "Geometry Runners") }
    func testRendering112Geophylla() async throws { try await verifyCollection("0x02f518c529a0002e505000795d00c500eb00534a1", name: "Geophylla") }
    func testRendering113GiftOfTime() async throws { try await verifyCollection("0x000000dc68934ed27fd11e32491cdf6717acaf211", name: "Gift of Time") }
    func testRendering114Gravity16() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270165", name: "Gravity 16") }
    func testRendering115GravityGrid() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd27045", name: "Gravity Grid") }
    func testRendering116Grit() async throws { try await verifyCollection("0x68c01cb4733a82a58d5e7bb31bddbff26a3a35d537", name: "Grit") }
    func testRendering117HalfHalfHalf() async throws { try await verifyCollection("0x68c01cb4733a82a58d5e7bb31bddbff26a3a35d521", name: "Half Half Half") }
    func testRendering118Hash() async throws { try await verifyCollection("0x47a91457a3a1f700097199fd63c039c4784384ab95", name: "Hash") }
    func testRendering119HashCrash() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270248", name: "HashCrash") }
    func testRendering120HaywireCafe() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270262", name: "Haywire Café ") }
    func testRendering121Heartbeat() async throws { try await verifyCollection("0x8db6f700a7c90000f92ac90084ad93a500f1eae00", name: "Heartbeat") }
    func testRendering122Hieroglyphs() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd27030", name: "Hieroglyphs") }
    func testRendering123Himinn() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270171", name: "Himinn") }
    func testRendering124Home() async throws { try await verifyCollection("0x68c01cb4733a82a58d5e7bb31bddbff26a3a35d530", name: "Home") }
    func testRendering125House() async throws { try await verifyCollection("0x68c01cb4733a82a58d5e7bb31bddbff26a3a35d535", name: "House") }
    func testRendering126HyperDriveASide() async throws { try await verifyCollection("0x99a9b7c1116f9ceeb1652de04d5969cce509b069392", name: "Hyper Drive: A-Side") }
    func testRendering127Hypertype() async throws { try await verifyCollection("0xbb5471c292065d3b01b2e81e299267221ae9a2500", name: "Hypertype") }
    func testRendering128ISawItInADream() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270102", name: "I Saw It in a Dream") }
    func testRendering129Ieva() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270339", name: "Ieva") }
    func testRendering130IfYouCouldDoItAllAgain() async throws { try await verifyCollection("0x0a1bbd57033f57e7b6743621b79fcb9eb2ce367658", name: "If You Could Do It All Again") }
    func testRendering131Imperfections() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270303", name: "Imperfections") }
    func testRendering132Implications() async throws { try await verifyCollection("0x99a9b7c1116f9ceeb1652de04d5969cce509b069395", name: "Implications") }
    func testRendering133Incantation() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd27082", name: "Incantation") }
    func testRendering134Incircles() async throws { try await verifyCollection("0x000000ff2fbc55b982010b42e235cc2a0ce3250b0", name: "Incircles") }
    func testRendering135Integration() async throws { try await verifyCollection("0x47a91457a3a1f700097199fd63c039c4784384ab16", name: "Integration") }
    func testRendering136IntoTheLight() async throws { try await verifyCollection("0x0000f6bc84ab98fbd8fce1f6d047965c723f00000", name: "Into the Light") }
    func testRendering137Intricada() async throws { try await verifyCollection("0x0a1bbd57033f57e7b6743621b79fcb9eb2ce367637", name: "Intricada") }
    func testRendering138Isodream() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270274", name: "Isodream") }
    func testRendering139Jazz() async throws { try await verifyCollection("0x000000412217f67742376769695498074f007b970", name: "jazz") }
    func testRendering140Labyrometry() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270127", name: "Labyrometry") }
    func testRendering141Lacunae() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270269", name: "Lacunae") }
    func testRendering142LargeShape() async throws { try await verifyCollection("0x68c01cb4733a82a58d5e7bb31bddbff26a3a35d514", name: "Large Shape") }
    func testRendering143LatentSpirits() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270329", name: "Latent Spirits") }
    func testRendering144LED() async throws { try await verifyCollection("0x0a1bbd57033f57e7b6743621b79fcb9eb2ce367643", name: "LED") }
    func testRendering145LeWittGeneratorGenerator() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270118", name: "LeWitt Generator Generator") }
    func testRendering146Libra() async throws { try await verifyCollection("0x99a9b7c1116f9ceeb1652de04d5969cce509b069398", name: "Libra") }
    func testRendering147LightweightReconstruction() async throws { try await verifyCollection("0x0000b52017e1ec58f64171b6001518c07a9aec000", name: "Lightweight Reconstruction") }
    func testRendering148Linea() async throws { try await verifyCollection("0x9800005deb3cfaf80077dbe9b9004c0020c1d6c51", name: "Linea") }
    func testRendering149LinesOfMemories() async throws { try await verifyCollection("0x9f79e46a309f804aa4b7b53a1f72c691374277943", name: "Lines of Memories") }
    func testRendering150LiquidRuminations() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270278", name: "Liquid Ruminations") }
    func testRendering151LittleBoxesOnTheHillsidesChild() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270185", name: "little boxes on the hillsides, child") }
    func testRendering152Longing() async throws { try await verifyCollection("0x99a9b7c1116f9ceeb1652de04d5969cce509b069413", name: "Longing") }
    func testRendering153Loom() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270213", name: "Loom") }
    func testRendering154LOVE() async throws { try await verifyCollection("0x4d928ab507bf633dd8e68024a1fb4c99316bbdf30", name: "LOVE") }
    func testRendering155MarfaYucca() async throws { try await verifyCollection("0x942bc2d3e7a589fe5bd4a5c6ef9727dfd82f5c8a1", name: "Marfa Yucca") }
    func testRendering156Meaningless() async throws { try await verifyCollection("0x99a9b7c1116f9ceeb1652de04d5969cce509b069444", name: "Meaningless") }
    func testRendering157MechanicalDrawing() async throws { try await verifyCollection("0x000009bb1740eea484f7db00000a9227e578bf964", name: "Mechanical Drawing") }
    func testRendering158MelancholicMagicalMaiden() async throws { try await verifyCollection("0x99a9b7c1116f9ceeb1652de04d5969cce509b069493", name: "Melancholic Magical Maiden") }
    func testRendering159MeltIntoYou() async throws { try await verifyCollection("0x47a91457a3a1f700097199fd63c039c4784384ab5", name: "Melt Into You") }
    func testRendering160MemoriasDelEspacioOlvidado() async throws { try await verifyCollection("0x1353fd9d3dc70d1a18149c8fb2adb4fb906de4e82", name: "Memorias del espacio olvidado") }
    func testRendering161MentalEntanglement() async throws { try await verifyCollection("0x47a91457a3a1f700097199fd63c039c4784384ab231", name: "Mental Entanglement") }
    func testRendering162MentalPathways() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270190", name: "Mental pathways") }
    func testRendering163Metaphysics() async throws { try await verifyCollection("0x99a9b7c1116f9ceeb1652de04d5969cce509b069382", name: "Metaphysics") }
    func testRendering164Miragem() async throws { try await verifyCollection("0x99a9b7c1116f9ceeb1652de04d5969cce509b069389", name: "Miragem") }
    func testRendering165Misbah() async throws { try await verifyCollection("0x0000000c687f0226eaf0bdb39104fad56738cdf20", name: "Misbah") }
    func testRendering166MisterShiftyAndTheDriftyDudes() async throws { try await verifyCollection("0x1725dc55c1bd5200bf00566cf20000b10800c68e0", name: "Mister Shifty and the Drifty Dudes") }
    func testRendering167MotionPictures() async throws { try await verifyCollection("0x000000637fddcdd459b047897afb3ea46aa6f3340", name: "Motion Pictures") }
    func testRendering168MuranoFantasy() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270193", name: "Murano Fantasy") }
    func testRendering169Naive() async throws { try await verifyCollection("0x99a9b7c1116f9ceeb1652de04d5969cce509b069483", name: "Naïve") }
    func testRendering170Nausea() async throws { try await verifyCollection("0x68c01cb4733a82a58d5e7bb31bddbff26a3a35d527", name: "Nausea") }
    func testRendering171Nebula() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270210", name: "Nebula") }
    func testRendering172Neighborhood() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270146", name: "Neighborhood") }
    func testRendering173NetNetNet() async throws { try await verifyCollection("0x99a9b7c1116f9ceeb1652de04d5969cce509b069441", name: "Net Net Net") }
    func testRendering174NthCulture() async throws { try await verifyCollection("0x0a1bbd57033f57e7b6743621b79fcb9eb2ce367618", name: "nth culture") }
    func testRendering175OdeToRoy() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd27063", name: "Ode to Roy") }
    func testRendering176OdeToUntitled() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270359", name: "Ode to Untitled") }
    func testRendering177Ofrenda() async throws { try await verifyCollection("0x00002491b000aa008756652c87cc92d87e896f0f0", name: "Ofrenda") }
    func testRendering178OnChainChain() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270283", name: "OnChainChain") }
    func testRendering179OpenClose() async throws { try await verifyCollection("0x68c01cb4733a82a58d5e7bb31bddbff26a3a35d524", name: "Open Close") }
    func testRendering180Optimism() async throws { try await verifyCollection("0x1d0977e86c70eabb5c8fd98db1b08c6d60caa0c11", name: "Optimism") }
    func testRendering181Orbifold() async throws { try await verifyCollection("0x0a1bbd57033f57e7b6743621b79fcb9eb2ce367645", name: "Orbifold") }
    func testRendering182Pages() async throws { try await verifyCollection("0x68c01cb4733a82a58d5e7bb31bddbff26a3a35d51", name: "Pages") }
    func testRendering183Parade() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270197", name: "Parade") }
    func testRendering184Passages() async throws { try await verifyCollection("0x0a1bbd57033f57e7b6743621b79fcb9eb2ce367638", name: "Passages") }
    func testRendering185PatchworkSaguaros() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd27066", name: "Patchwork Saguaros") }
    func testRendering186PatternsOfLife() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd27087", name: "Patterns of Life") }
    func testRendering187Pax() async throws { try await verifyCollection("0xd40030fd1d00f1a9944462ff0025e9c8d00035000", name: "Pax") }
    func testRendering188Perpetua() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270277", name: "Perpetua") }
    func testRendering189PigSTail() async throws { try await verifyCollection("0x47a91457a3a1f700097199fd63c039c4784384ab12", name: "Pig's Tail") }
    func testRendering190PixelGlass() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd27024", name: "Pixel Glass") }
    func testRendering191PoolParty() async throws { try await verifyCollection("0xaa00b2b2db36b8f8004a9aa96f0012005d92b3000", name: "pool party") }
    func testRendering192Portal() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd27094", name: "Portal") }
    func testRendering193Progression() async throws { try await verifyCollection("0x000009bb1740eea484f7db00000a9227e578bf963", name: "Progression") }
    func testRendering194Proscenium() async throws { try await verifyCollection("0x99a9b7c1116f9ceeb1652de04d5969cce509b069486", name: "Proscenium") }
    func testRendering195Pulse() async throws { try await verifyCollection("0x68c01cb4733a82a58d5e7bb31bddbff26a3a35d536", name: "Pulse") }
    func testRendering196QuantumCollapses() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270275", name: "Quantum Collapses") }
    func testRendering197QuantumCirclet() async throws { try await verifyCollection("0x47a91457a3a1f700097199fd63c039c4784384ab277", name: "QuantumCirclet ") }
    func testRendering198Quarantine() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270183", name: "Quarantine") }
    func testRendering199QWERTY() async throws { try await verifyCollection("0x64780ce53f6e966e18a22af13a2f97369580ec112", name: "QWERTY") }
    func testRendering200RainBlooms() async throws { try await verifyCollection("0x70270e65bc37832ef845fa330c2b71501970dab90", name: "Rain Blooms") }
    func testRendering201RAINBOWS() async throws { try await verifyCollection("0x47a91457a3a1f700097199fd63c039c4784384ab268", name: "RAINBOWS") }
    func testRendering202Rapture() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270141", name: "Rapture") }
    func testRendering203Ratio() async throws { try await verifyCollection("0x0000528a4a3859020a7970110c16941a00fadf000", name: "Ratio") }
    func testRendering204ReceiveTransmission() async throws { try await verifyCollection("0x294fed5f1d3d30cfa6fe86a937dc3141eec8bc6d4", name: "Receive Transmission") }
    func testRendering205Reflection() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270208", name: "Reflection") }
    func testRendering206Retrometrix() async throws { try await verifyCollection("0x47a91457a3a1f700097199fd63c039c4784384ab51", name: "Retrometrix") }
    func testRendering207Rhythm() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd27057", name: "Rhythm") }
    func testRendering208Rinascita() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270121", name: "Rinascita") }
    func testRendering209Ripple() async throws { try await verifyCollection("0x68c01cb4733a82a58d5e7bb31bddbff26a3a35d534", name: "Ripple") }
    func testRendering210Rooms() async throws { try await verifyCollection("0x68c01cb4733a82a58d5e7bb31bddbff26a3a35d540", name: "Rooms") }
    func testRendering211Rotae() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270194", name: "Rotae") }
    func testRendering212Rotor() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270315", name: "Rotor") }
    func testRendering213Rubicon() async throws { try await verifyCollection("0x0a1bbd57033f57e7b6743621b79fcb9eb2ce367617", name: "Rubicon") }
    func testRendering214Sandaliya() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270366", name: "Sandaliya") }
    func testRendering215Screens() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270255", name: "Screens") }
    func testRendering216ScribbledBoundaries() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270131", name: "Scribbled Boundaries") }
    func testRendering217ScribbledDaydreams() async throws { try await verifyCollection("0xa319c382a702682129fcbf55d514e61a16f97f9c19", name: "Scribbled Daydreams") }
    func testRendering218Scribblines() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270335", name: "Scribblines") }
    func testRendering219Seasky() async throws { try await verifyCollection("0x99a9b7c1116f9ceeb1652de04d5969cce509b069459", name: "Seasky") }
    func testRendering220Shields() async throws { try await verifyCollection("0xa319c382a702682129fcbf55d514e61a16f97f9c15", name: "Shields") }
    func testRendering221Sigils() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd27093", name: "Sigils") }
    func testRendering222Sinking() async throws { try await verifyCollection("0x68c01cb4733a82a58d5e7bb31bddbff26a3a35d50", name: "Sinking") }
    func testRendering223SKEUOMORPHS() async throws { try await verifyCollection("0x99a9b7c1116f9ceeb1652de04d5969cce509b069422", name: "SKEUOMORPHS") }
    func testRendering224SonoranRoadways() async throws { try await verifyCollection("0x99a9b7c1116f9ceeb1652de04d5969cce509b069461", name: "Sonoran Roadways") }
    func testRendering225SpaceBirds() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270177", name: "Space Birds") }
    func testRendering226SpaceDebrisMAider() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd27079", name: "Space Debris [m'aider]") }
    func testRendering227Spaghettification() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd27099", name: "Spaghettification") }
    func testRendering228SpeckledSummits() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270109", name: "Speckled Summits") }
    func testRendering229SpiroFlakes() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270136", name: "SpiroFlakes") }
    func testRendering230Staccato() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270351", name: "Staccato") }
    func testRendering231StarFlower() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd27052", name: "Star Flower") }
    func testRendering232Stellaraum() async throws { try await verifyCollection("0x0a1bbd57033f57e7b6743621b79fcb9eb2ce36761", name: "Stellaraum") }
    func testRendering233StillMoving() async throws { try await verifyCollection("0x99a9b7c1116f9ceeb1652de04d5969cce509b069433", name: "Still Moving") }
    func testRendering234StippleSunsets() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd27051", name: "Stipple Sunsets") }
    func testRendering235Stretch() async throws { try await verifyCollection("0x68c01cb4733a82a58d5e7bb31bddbff26a3a35d528", name: "Stretch") }
    func testRendering236Striation() async throws { try await verifyCollection("0x47a91457a3a1f700097199fd63c039c4784384ab75", name: "striation") }
    func testRendering237Structures() async throws { try await verifyCollection("0xa319c382a702682129fcbf55d514e61a16f97f9c16", name: "Structures") }
    func testRendering238SuchALovelyTime() async throws { try await verifyCollection("0x99a9b7c1116f9ceeb1652de04d5969cce509b069400", name: "Such A Lovely Time") }
    func testRendering239Sudfah() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270328", name: "Sudfah") }
    func testRendering240SummoningRitual() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270236", name: "Summoning Ritual") }
    func testRendering241Swing() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270184", name: "Swing") }
    func testRendering242Synapses() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd27039", name: "Synapses") }
    func testRendering243SystemsMadness() async throws { try await verifyCollection("0x99a9b7c1116f9ceeb1652de04d5969cce509b069442", name: "Systems Madness") }
    func testRendering244Testo() async throws { try await verifyCollection("0x9800005deb3cfaf80077dbe9b9004c0020c1d6c52", name: "Testo") }
    func testRendering245TheCollectorSRoom() async throws { try await verifyCollection("0x1353fd9d3dc70d1a18149c8fb2adb4fb906de4e814", name: "The Collector's Room") }
    func testRendering246TheDestination() async throws { try await verifyCollection("0x0a1bbd57033f57e7b6743621b79fcb9eb2ce367681", name: "The Destination") }
    func testRendering247TheDistanceInBetween() async throws { try await verifyCollection("0x47a91457a3a1f700097199fd63c039c4784384ab6", name: "The Distance in Between") }
    func testRendering248TheHarvest() async throws { try await verifyCollection("0x99a9b7c1116f9ceeb1652de04d5969cce509b069407", name: "The Harvest") }
    func testRendering249TheLightWhereWeMeet() async throws { try await verifyCollection("0x00000041a2980e05cb4fbbbc735f17eff443b5920", name: "The light where we meet") }
    func testRendering250TheNursery() async throws { try await verifyCollection("0x0a1bbd57033f57e7b6743621b79fcb9eb2ce36767", name: "The Nursery") }
    func testRendering251TheSpringBeginsWithTheFirstRainstorm() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270317", name: "the spring begins with the first rainstorm") }
    func testRendering252ThemesAndVariations() async throws { try await verifyCollection("0xe034bb2b1b9471e11cf1a0a9199a156fb227aa5d0", name: "Themes and Variations") }
    func testRendering253TheoreticalTownships() async throws { try await verifyCollection("0x9f79e46a309f804aa4b7b53a1f72c691374277942", name: "Theoretical Townships") }
    func testRendering254ThoughtsOfMeadow() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270355", name: "Thoughts of Meadow") }
    func testRendering255Thread() async throws { try await verifyCollection("0x8ce22a649a0ea5008900740028007278038d00230", name: "Thread") }
    func testRendering256ThroughMyWindshield() async throws { try await verifyCollection("0x47a91457a3a1f700097199fd63c039c4784384ab38", name: "Through my windshield") }
    func testRendering257ThroughTheWindow() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270207", name: "Through the Window") }
    func testRendering258TidePredictor() async throws { try await verifyCollection("0x99a9b7c1116f9ceeb1652de04d5969cce509b069376", name: "Tide Predictor") }
    func testRendering259TigerbobCharmPacks() async throws { try await verifyCollection("0x000056c200618b979900c3f1ef9aef86f4c47eaa1", name: "Tigerbob Charm Packs") }
    func testRendering260TigerbobMysteryGarden() async throws { try await verifyCollection("0x000056c200618b979900c3f1ef9aef86f4c47eaa0", name: "Tigerbob Mystery Garden") }
    func testRendering261TimeSquared() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270237", name: "Time Squared") }
    func testRendering262TimeTravelInASubconsciousMind() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270271", name: "Time travel in a subconscious mind") }
    func testRendering263Torrent() async throws { try await verifyCollection("0x99a9b7c1116f9ceeb1652de04d5969cce509b069466", name: "Torrent") }
    func testRendering264Trademark() async throws { try await verifyCollection("0x8cdbd7010bd197848e95c1fd7f6e870aac9b0d3c4", name: "Trademark") }
    func testRendering265TransformationsDuChamp() async throws { try await verifyCollection("0x000000b394cac6057d87df835bea27844b3e28280", name: "Transformations du Champ") }
    func testRendering266Transit() async throws { try await verifyCollection("0x68c01cb4733a82a58d5e7bb31bddbff26a3a35d539", name: "Transit") }
    func testRendering267Transit() async throws { try await verifyCollection("0x47a91457a3a1f700097199fd63c039c4784384ab90", name: "Transit") }
    func testRendering268TranslucentPanes() async throws { try await verifyCollection("0x0a1bbd57033f57e7b6743621b79fcb9eb2ce367612", name: "translucent panes") }
    func testRendering269Trossets() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270147", name: "Trossets") }
    func testRendering270TurnerInTheLight() async throws { try await verifyCollection("0x47a91457a3a1f700097199fd63c039c4784384ab108", name: "Turner in the Light") }
    func testRendering271UltraWave369() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270157", name: "UltraWave 369") }
    func testRendering272UMK() async throws { try await verifyCollection("0x99a9b7c1116f9ceeb1652de04d5969cce509b069436", name: "UMK") }
    func testRendering273Uniqueness() async throws { try await verifyCollection("0x47a91457a3a1f700097199fd63c039c4784384ab310", name: "Uniqueness") }
    func testRendering274Utopia() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd27015", name: "Utopia") }
    func testRendering275Vahria() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270340", name: "Vahria") }
    func testRendering276Vaxt() async throws { try await verifyCollection("0x99a9b7c1116f9ceeb1652de04d5969cce509b069488", name: "Växt") }
    func testRendering277Vessel() async throws { try await verifyCollection("0x47a91457a3a1f700097199fd63c039c4784384ab255", name: "vessel") }
    func testRendering278ViewCard() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd2706", name: "View Card") }
    func testRendering279VIVOTECA() async throws { try await verifyCollection("0x00000024ca7f3cfba7084e3289a9048d79261b290", name: "VIVOTECA") }
    func testRendering280Void() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd27042", name: "Void") }
    func testRendering281Volute() async throws { try await verifyCollection("0x99a9b7c1116f9ceeb1652de04d5969cce509b069394", name: "Volute") }
    func testRendering282Vortex() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270225", name: "Vortex") }
    func testRendering283Voyager() async throws { try await verifyCollection("0x99a9b7c1116f9ceeb1652de04d5969cce509b069434", name: "Voyager") }
    func testRendering284Warp() async throws { try await verifyCollection("0x68c01cb4733a82a58d5e7bb31bddbff26a3a35d513", name: "Warp") }
    func testRendering285Warp() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270154", name: "Warp") }
    func testRendering286WatercolorDreams() async throws { try await verifyCollection("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd27059", name: "Watercolor Dreams") }
    func testRendering287WhileTrue() async throws { try await verifyCollection("0xab0000000000aa06f89b268d604a9c1c41524ac6498", name: "while true") }
    func testRendering288WhispersOfMotionFiatPass() async throws { try await verifyCollection("0x47a91457a3a1f700097199fd63c039c4784384ab299", name: "Whispers of Motion: Fiat Pass") }
    func testRendering289Winterkammer() async throws { try await verifyCollection("0x000000c9572b8a9a638f238510af4e90a4e365ee1", name: "Winterkammer") }
    func testRendering290Worlds() async throws { try await verifyCollection("0x13aae6f9599880edbb7d144bb13f1212cee995330", name: "Worlds") }
    func testRendering291YouAreHerePart1() async throws { try await verifyCollection("0x47a91457a3a1f700097199fd63c039c4784384ab270", name: "You Are Here (Part 1)") }
    func testRendering292Zoom() async throws { try await verifyCollection("0x68c01cb4733a82a58d5e7bb31bddbff26a3a35d532", name: "Zoom") }

    private func verifyCollection(_ id: String, name: String) async throws {
        let resources = try resources(id)
        XCTAssertEqual(resources.script.name, name)
        XCTAssertGreaterThanOrEqual(resources.tokens.count, 2)
        let firstToken = try XCTUnwrap(resources.tokens.first)
        let initialSize = try size(for: firstToken)
        let fixture = try RenderingFixture(size: initialSize)
        defer { fixture.close() }
        AutoReloadingWebView.resetStartupCalibrationsForTesting()
        let profile = ArtBlocksRenderingStartupProfiles.startupProfile(resources.script)
        for (phase, index) in [("first", 0), ("next", 1), ("new-middle", resources.tokens.count / 2), ("new-last", resources.tokens.count - 1), ("revisit", 0)] {
            let token = resources.tokens[index]
            let size = try size(for: token)
            let previousDocuments = fixture.probe.documents.count
            let started = Date()
            fixture.load(script: resources.script, token: token, size: size)
            XCTAssertTrue(fixture.loadedHTML.contains(resources.script.value), "\(name) artist source changed")
            let first = try await waitForAppearance(fixture, script: resources.script, token: token,
                after: previousDocuments, started: started)
            let appearanceMilliseconds = Date().timeIntervalSince(started) * 1000
            var observations = [first]
            for _ in 0..<3 {
                try await Task.sleep(for: .milliseconds(100))
                observations.append(try await fixture.snapshot())
            }
            let documents = Array(fixture.probe.documents.dropFirst(previousDocuments))
            XCTAssertFalse(documents.isEmpty, "\(name) \(phase) did not load a document")
            XCTAssertEqual(documents.count, 1, "\(name) \(phase) unexpectedly reloaded")
            for document in documents {
                XCTAssertEqual(document["tokenId"] as? String, token.id, "\(name) \(phase) wrong document token")
                XCTAssertEqual(document["hash"] as? String, token.hash, "\(name) \(phase) wrong document hash")
            }
            for observation in observations {
                XCTAssertEqual(observation["tokenId"] as? String, token.id, "\(name) \(phase) wrong token")
                XCTAssertEqual(observation["hash"] as? String, token.hash, "\(name) \(phase) wrong hash")
                let width = (observation["width"] as? NSNumber)?.doubleValue ?? 0
                let height = (observation["height"] as? NSNumber)?.doubleValue ?? 0
                XCTAssertTrue(width.isFinite && width > 0, "\(name) \(phase) invalid viewport width")
                XCTAssertTrue(height.isFinite && height > 0, "\(name) \(phase) invalid viewport height")
                if profile != nil {
                    XCTAssertEqual(observation["generation"] as? String, first["generation"] as? String,
                        "\(name) \(phase) restarted after stable presentation")
                }
            }
            if profile != nil {
                XCTAssertTrue(fixture.webView.artworkIsPresented, "\(name) \(phase) covered its presented artwork")
            }
            XCTAssertTrue(fixture.errors.isEmpty, "\(name) \(phase): \(fixture.errors.joined(separator: "; "))")
            let evidence: [String: Any] = [
                "name": name, "collectionId": id, "phase": phase, "tokenIndex": index,
                "tokenId": token.id, "tokenHash": token.hash ?? "",
                "artistSourceSHA256": SHA256.hash(data: Data(resources.script.value.utf8)).map { String(format: "%02x", $0) }.joined(),
                "profile": profile != nil, "nativeSize": [Double(size.width), Double(size.height)],
                "screenScale": Double(fixture.window.screen.scale), "pageZoom": Double(fixture.webView.pageZoom),
                "appearanceMilliseconds": appearanceMilliseconds, "documents": documents,
                "observations": observations, "errors": fixture.errors
            ]
            attachJSON(evidence, name: "\(name) \(phase) production rendering")
            if phase == "first" {
                let screenshot = XCTAttachment(data: try await fixture.screenshot(), uniformTypeIdentifier: "public.png")
                screenshot.name = "\(name) first artwork"
                screenshot.lifetime = .keepAlways
                add(screenshot)
            }
            let result: [String: Any] = ["name": name, "collectionId": id, "phase": phase,
                "tokenId": token.id, "profile": profile != nil, "documentCount": documents.count,
                "appearanceMilliseconds": appearanceMilliseconds, "errors": fixture.errors]
            print("FINAL_REVIEW_MATRIX_JSON \(String(decoding: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), as: UTF8.self))")
        }
        XCTAssertEqual(try Data(contentsOf: resources.scriptURL), resources.source)
        XCTAssertEqual(try Data(contentsOf: resources.tokensURL), resources.tokenData)
    }

    private func resources(_ id: String) throws -> Resources {
        let scriptURL = try XCTUnwrap(SuggestedItemsService.bundle.url(forResource: "Scripts/\(id)", withExtension: "json"))
        let tokensURL = try XCTUnwrap(SuggestedItemsService.bundle.url(forResource: "Tokens/\(id)", withExtension: "json"))
        let source = try Data(contentsOf: scriptURL), tokenData = try Data(contentsOf: tokensURL)
        return Resources(script: try JSONDecoder().decode(Script.self, from: source),
            tokens: try JSONDecoder().decode(BundledTokens.self, from: tokenData).items,
            scriptURL: scriptURL, tokensURL: tokensURL, source: source, tokenData: tokenData)
    }

    private func size(for token: BundledTokens.Item) throws -> CGSize {
        let ratio = try XCTUnwrap(token.artworkAspectRatio ?? token.thumbnailAspectRatio)
        return CGSize(width: 300, height: 300 / ratio.value)
    }

    private func waitForAppearance(
        _ fixture: RenderingFixture, script: Script, token: BundledTokens.Item,
        after previousDocuments: Int, started: Date
    ) async throws -> [String: Any] {
        let heavy = ["Cushions", "Gift of Time", "Classical Revival", "Into the Light", "Inhabitants", "Bauhaus Synthesis", "Fermented Fruit"]
        let deadline = started.addingTimeInterval(heavy.contains(script.name) ? 60 : 20)
        let calibrated = fixture.webView.usesStableArtworkPresentation
        while Date() < deadline {
            if !fixture.errors.isEmpty {
                throw NSError(domain: "FinalReviewArtworkError", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "\(script.name): \(fixture.errors.joined(separator: "; "))"])
            }
            if fixture.probe.documents.count > previousDocuments,
               !calibrated || fixture.webView.artworkIsPresented {
                do {
                    let snapshot = try await fixture.snapshot()
                    if snapshot["ready"] as? Bool == true,
                       snapshot["tokenId"] as? String == token.id,
                       snapshot["hash"] as? String == token.hash {
                        return snapshot
                    }
                } catch {
                    guard (error as NSError).domain == "FinalReviewEvaluationTimeout" else { throw error }
                }
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        let snapshot = try? await fixture.snapshot()
        if let snapshot { attachJSON(snapshot, name: "\(script.name) first appearance timeout") }
        throw NSError(domain: "FinalReviewAppearanceTimeout", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "\(script.name) did not present a visible drawing, DOM, SVG, or decoded media before the deadline"])
    }

    private func attachJSON(_ value: [String: Any], name: String) {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]) else {
            XCTFail("Could not encode \(name)")
            return
        }
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
