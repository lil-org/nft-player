// ∅ 2026 lil org

import CryptoKit
import Foundation

nonisolated enum RawHtmlGenerator {
    
    private static func libScript(_ kind: Script.Kind) -> String {
        guard let library = PersistentJavaScriptLibrary.library(named: kind.rawValue) else { return "" }
        return PersistentJavaScriptLibrary.reference(for: library)
    }

    private static let embeddedP5Pattern = #"<script\s+src=["']https://cdnjs\.cloudflare\.com/ajax/libs/p5\.js/1\.4\.0/p5(?:\.min)?\.js["']\s*>\s*</script>"#

    static func requiredDependencies(for script: Script) -> [PersistentArtworkDependency] {
        guard !script.kind.isNativeRenderer else { return [] }
        var kinds = (script.additionalLibraries ?? []).filter { $0 != script.kind && $0 != .three167 }
        if script.kind == .html, script.value.range(of: embeddedP5Pattern, options: .regularExpression) != nil {
            kinds.append(.p5js140)
        } else {
            kinds.append(script.kind)
        }
        var dependencies: [PersistentArtworkDependency] = []
        for kind in kinds {
            if let library = PersistentJavaScriptLibrary.library(named: kind.rawValue), !dependencies.contains(library) {
                dependencies.append(library)
            }
        }
        if !persistentHypertypeDependency(script).isEmpty { dependencies.append(.hypertype) }
        return dependencies
    }

    static func createHtml(
        script: Script,
        token: BundledTokens.Item,
        forceLibScript: String? = nil,
        libraryScriptProvider: ((Script.Kind) -> String?)? = nil
    ) -> String {
        guard !script.kind.isNativeRenderer else { return "" }
        guard let hash = token.hash else { return "" }

        let id = token.id
        let libraryScript: (Script.Kind) -> String = { kind in
            libraryScriptProvider?(kind) ?? Self.libScript(kind)
        }
        let libScript = forceLibScript ?? libraryScript(script.kind)
        let viewport =
            """
            <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1"/>
            """

        let tuning = {
            if let nftPlayerDisplayTuning = script.nftPlayerDisplayTuning {
                return "\n<script>\(nftPlayerDisplayTuning)</script>\n"
            } else {
                return ""
            }
        }()
        
        let tokenData: String
        if script.usesArtBlocksRenderer {
            tokenData = artBlocksTokenData(script: script, token: token, hash: hash)
        } else if script.address == "0x059edd72cd353df5106d2b9cc5ab83a52287ac3a" {
            tokenData =
                """
                let tokenData = {"tokenId": "\(id)", "hashes": ["\(hash)"]}
                """
        } else {
            tokenData =
                """
                let tokenData = {"tokenId": "\(id)", "hash": "\(hash)"}
                """
        }
        
        let html: String
        switch script.kind {
        case .html:
            var document = script.value
            if let libraryTag = document.range(
                of: embeddedP5Pattern,
                options: .regularExpression
            ) {
                document.replaceSubrange(
                    libraryTag,
                    with: "<script>\(escapedInlineLibrary(libraryScript(.p5js140)))</script>"
                )
            }
            html = insertingInHead(
                """
                \(viewport)
                <style>html, body { width: 100%; height: 100%; margin: 0; padding: 0; overflow: hidden; } canvas { display: block; position: absolute; inset: 0; margin: auto; max-width: 100vw; max-height: 100vh; object-fit: contain; }</style>
                <script>\(tokenData)</script>\(tuning)
                """,
                into: document
            )
        case .svg:
            html =
            """
            <html>
            <head>
              \(viewport)
              <meta charset="utf-8">
              <style type="text/css">
                body {
                  min-height: 100%;
                  margin: 0;
                  padding: 0;
                }
                svg {
                  padding: 0;
                  margin: auto;
                  display: block;
                  position: absolute;
                  top: 0;
                  bottom: 0;
                  left: 0;
                  right: 0;
                }
              </style>
            </head>
            <body></body>
            <script>\(tokenData)</script>
            <script>\(script.value)</script>\(tuning)
            </html>
            """
        case .js:
            html =
            """
            <html>
            <head>
              \(viewport)
              <meta charset="utf-8">
              <script>\(tokenData)</script>
              <style type="text/css">
                body {
                  margin: 0;
                  padding: 0;
                }
                canvas {
                  padding: 0;
                  margin: auto;
                  display: block;
                  position: absolute;
                  top: 0;
                  bottom: 0;
                  left: 0;
                  right: 0;
                }
              </style>
            </head>
            <body>
              \(script.requiresInitialCanvas == false ? "" : "<canvas></canvas>")
              <script>\(script.value)</script>\(tuning)
            </body>
            </html>
            """
        case .processingjs146:
            html =
            """
            <html>
            <head>
              \(viewport)
              <meta charset="utf-8">
              <script>\(libScript)</script>
              <script>\(tokenData)</script>
              <style>
                html { height: 100%; }
                body { min-height: 100%; margin: 0; padding: 0; }
                canvas { display: block; margin: auto; padding: 0; position: absolute; inset: 0; }
              </style>
            </head>
            <body>
              <script type="application/processing">\(script.value)</script>
              <canvas></canvas>\(tuning)
            </body>
            </html>
            """
        case .p5js100, .p5js190, .p5js140, .p5js11111, .p5js160:
            html =
            """
            <html>
            <head>
              \(viewport)
              <meta charset="utf-8">
              <script>\(libScript)</script>
              <script>\(tokenData)</script>
              <script>\(script.value)</script>\(tuning)
              <style type="text/css">
                html {
                  height: 100%;
                }
                body {
                  min-height: 100%;
                  margin: 0;
                  padding: 0;
                }
                canvas {
                  padding: 0;
                  margin: auto;
                  display: block;
                  position: absolute;
                  top: 0;
                  bottom: 0;
                  left: 0;
                  right: 0;
                }
              </style>
            </head>
            </html>
            """
        case .paper:
            html =
            """
            <html>
            <head>
                \(viewport)
                <meta charset="utf-8"/>
                <script>\(libScript)</script>
                <script>\(tokenData)</script>
                <script>\(script.value)</script>\(tuning)
                    <style type="text/css">
                    html {
                        height: 100%;
                    }

                    body {
                        min-height: 100%;
                        margin: 0;
                        padding: 0;
                    }

                    canvas {
                        padding: 0;
                        margin: auto;
                        display: block;
                        position: absolute;
                        top: 0;
                        bottom: 0;
                        left: 0;
                        right: 0;
                    }
                    </style>
                </head>
                </html>
            """
        case .three, .three160, .three155:
            html =
            """
            <html>
              <head>
                \(viewport)
                <script>\(libScript)</script>
                <meta charset="utf-8">
                <style type="text/css">
                  body {
                    margin: 0;
                    padding: 0;
                  }
                  canvas {
                    padding: 0;
                    margin: auto;
                    display: block;
                    position: absolute;
                    top: 0;
                    bottom: 0;
                    left: 0;
                    right: 0;
                  }
                </style>
              </head>
              <body></body>
              <script>\(tokenData)</script>
              <script>\(script.value)</script>\(tuning)
            </html>
            """
        case .three167:
            html =
            """
            <html>
            <head>
              \(viewport)
              <meta charset="utf-8">
              <script>\(tokenData)</script>
              \(moduleImportMap(script: script, threeLibrary: libScript))
              <style>html, body { margin: 0; padding: 0; min-height: 100%; } canvas { display: block; margin: auto; padding: 0; position: absolute; inset: 0; }</style>
            </head>
            <body>
              <script\(script.isModule == true ? " type=\"module\"" : "")>\(script.value)</script>\(tuning)
            </body>
            </html>
            """
        case .babylon500:
            html =
            """
            <html>
            <head>
              \(viewport)
              <meta charset="utf-8">
              <script>\(libScript)</script>
              <script>\(tokenData)</script>
              <style>html, body { width: 100%; height: 100%; margin: 0; padding: 0; overflow: hidden; } #babylon-canvas { display: block; width: 100%; height: 100%; touch-action: none; outline: none; }</style>
            </head>
            <body>
              \(script.requiresInitialCanvas == false ? "" : "<canvas id=\"babylon-canvas\"></canvas>")
              <script>\(script.value)</script>\(tuning)
            </body>
            </html>
            """
        case .twemoji:
            html =
            """
            <html>
            <head>
                \(viewport)
                <meta charset="utf-8"/>
                <script>\(libScript)</script>
                <script>\(tokenData)</script>
                <script>\(script.value)</script>\(tuning)
                <style type="text/css">
                    html {
                        height: 100%;
                    }

                    body {
                        min-height: 100%;
                        margin: 0;
                        padding: 0;
                    }

                    canvas {
                        padding: 0;
                        margin: auto;
                        display: block;
                        position: absolute;
                        top: 0;
                        bottom: 0;
                        left: 0;
                        right: 0;
                    }
                    </style>
                </head>
                </html>
            """
        case .regl:
            html =
            """
            <html>
              <head>
                \(viewport)
                <script>\(libScript)</script>
                <script>\(tokenData)</script>
                <meta charset="utf-8">
                <style type="text/css">
                  body {
                    margin: 0;
                    padding: 0;
                  }
                  canvas {
                    padding: 0;
                    margin: auto;
                    display: block;
                    position: absolute;
                    top: 0;
                    bottom: 0;
                    left: 0;
                    right: 0;
                  }
                </style>
              </head>
              <body>
                <script>\(script.value)</script>\(tuning)
              </body>
            </html>
            """
        case .tone, .tone1504:
            html =
            """
            <html>
              <head>
                \(viewport)
                <script>\(libScript)</script>
                <meta charset="utf-8">
                <style type="text/css">
                  body {
                    margin: 0;
                    padding: 0;
                  }
                  canvas {
                    padding: 0;
                    margin: auto;
                    display: block;
                    position: absolute;
                    top: 0;
                    bottom: 0;
                    left: 0;
                    right: 0;
                  }
                </style>
              </head>
              <body>
                \(script.requiresInitialCanvas == false ? "" : "<canvas></canvas>")
              </body>
              <script>\(tokenData)</script>
              <script>\(script.value)</script>\(tuning)
            </html>
            """
        case .ort1140, .seedrandom305, .p5svg, .ponchoDrifellaNative, .cardNft2Native:
            html = ""
        }
        var resolvedHTML = html
        let beforeArtist = [
            ArtBlocksRenderingResolutionOverrides.beforeArtist(script),
            persistentHypertypeDependency(script),
            ArtBlocksRenderingStartupProfiles.beforeArtist(script)
        ].filter { !$0.isEmpty }.joined(separator: "\n")
        let afterArtist = [ArtBlocksRenderingResolutionOverrides.afterArtist(script),
                           ArtBlocksRenderingStartupProfiles.afterArtist(script)]
            .filter { !$0.isEmpty }.joined(separator: "\n")
        if !beforeArtist.isEmpty || !afterArtist.isEmpty {
            let artistType = script.kind == .processingjs146 ? " type=\"application/processing\"" : ""
            let artistTag = "<script\(artistType)>\(script.value)</script>"
            let before = beforeArtist.isEmpty ? "" : "<script>\(beforeArtist)</script>"
            let after = afterArtist.isEmpty ? "" : "<script>\(afterArtist)</script>"
            resolvedHTML = resolvedHTML.replacingOccurrences(of: artistTag, with: before + artistTag + after)
        }
        let additionalLibraries = (script.additionalLibraries ?? [])
            .filter { $0 != script.kind && $0 != .three167 }
            .map { "<script>\(libraryScript($0))</script>" }
            .joined(separator: "\n")
        let startupProfile = ArtBlocksRenderingStartupProfiles.startupProfile(script)
        let bootstrap = script.usesArtBlocksRenderer
            ? artworkErrorBootstrap(
                collectionId: script.id,
                tokenId: token.id,
                measuresProcessingSampling: ArtBlocksRenderingResolutionOverrides.usesProcessingRetinaCanvas(script),
                frameDrivenPresentation: startupProfile != nil
            )
            : ""
        let startup = startupProfile.map { profile in
            var fields = try! JSONSerialization.jsonObject(with: JSONEncoder().encode(profile)) as! [String: Any]
            fields["collectionId"] = script.id
            fields["tokenId"] = token.id
            let data = try! JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])
            return "<meta name=\"artblocks-review-startup\" content=\"\(data.base64EncodedString())\">" + artworkPresentationBootstrap
        } ?? ""
        guard !additionalLibraries.isEmpty || !bootstrap.isEmpty || !startup.isEmpty else { return resolvedHTML }
        return insertingInHead(bootstrap + startup + additionalLibraries, into: resolvedHTML)
    }

    private static let artworkPresentationBootstrap = """
    <script>
    (function () {
      const drawn = new WeakSet(), contexts = new WeakSet();
      const getContext = HTMLCanvasElement.prototype.getContext;
      HTMLCanvasElement.prototype.getContext = function () {
        const args = Array.from(arguments), kind = String(args[0]);
        args[0] = kind;
        const context = getContext.apply(this, args);
        if (!context || contexts.has(context)) return context;
        contexts.add(context);
        const methods = kind === "2d"
          ? ["fill", "stroke", "fillRect", "strokeRect", "drawImage", "putImageData", "fillText", "strokeText"]
          : ["drawArrays", "drawElements", "drawArraysInstanced", "drawElementsInstanced"];
        const originals = new Map(), canvas = this;
        methods.forEach(function (name) {
          const original = context[name];
          if (typeof original !== "function") return;
          const descriptor = Object.getOwnPropertyDescriptor(context, name);
          const wrapped = function () {
            const result = original.apply(this, arguments);
            drawn.add(canvas);
            scheduleInspection();
            originals.forEach(function (entry, method) {
              if (context[method] !== entry.wrapped) return;
              if (entry.descriptor) Object.defineProperty(context, method, entry.descriptor); else delete context[method];
            });
            originals.clear();
            return result;
          };
          Object.defineProperty(context, name, { configurable: true, writable: true, value: wrapped });
          originals.set(name, { descriptor: descriptor, wrapped: wrapped });
        });
        resizeObserver.observe(this);
        return context;
      };
      let frame, previous, sent, stopped = false;
      const metadata = JSON.parse(atob(document.querySelector('meta[name="artblocks-review-startup"]').content));
      const resizeObserver = new ResizeObserver(scheduleInspection);
      const mutations = new MutationObserver(scheduleInspection);
      resizeObserver.observe(document.documentElement);
      mutations.observe(document, { subtree: true, childList: true, attributes: true,
        attributeFilter: ["style", "class", "width", "height", "src"] });
      function scheduleInspection() {
        if (stopped || frame != null) return;
        frame = requestAnimationFrame(inspect);
      }
      function scheduleStyleInspection() {
        scheduleInspection();
        requestAnimationFrame(scheduleInspection);
      }
      function visible(element) {
        const rect = element.getBoundingClientRect();
        if (!(rect.width > 0 && rect.height > 0 && rect.right > 0 && rect.bottom > 0
            && rect.left < innerWidth && rect.top < innerHeight)) return false;
        for (let node = element; node; node = node.parentElement) {
          const style = getComputedStyle(node);
          if (style.display === "none" || style.visibility === "hidden" || Number(style.opacity) === 0) return false;
        }
        return true;
      }
      function inspect() {
        frame = null;
        if (stopped) return;
        const loading = document.getElementById("loading-overlay");
        const canvases = [...document.querySelectorAll("canvas")].filter(c => drawn.has(c) && visible(c));
        const nonCanvas = [...document.querySelectorAll("svg,video,img")].some(e => visible(e)
          && (e.tagName !== "IMG" || e.complete && e.naturalWidth > 0)
          && (e.tagName !== "VIDEO" || e.readyState >= 2));
        const ready = (!loading || !visible(loading)) && (canvases.length > 0 || nonCanvas);
        const signature = canvases.map(c => {
          const r = c.getBoundingClientRect(); return [c.width,c.height,r.x,r.y,r.width,r.height].join(":");
        }).join("|") + ":" + nonCanvas;
        if (ready) window.dispatchEvent(new Event("artBlocksPreviewInspectResolution"));
        if (ready && signature === previous && signature !== sent) {
          window.webkit?.messageHandlers.artBlocksPreviewPresentation?.postMessage({
            generation: window.__artBlocksPreviewGeneration,
            collectionId: metadata.collectionId, tokenId: metadata.tokenId,
            ready: true
          });
          sent = signature;
          stopInspection();
          return;
        }
        const needsAnotherFrame = ready && signature !== previous;
        previous = ready ? signature : null;
        if (needsAnotherFrame) scheduleInspection();
      }
      document.addEventListener("DOMContentLoaded", scheduleInspection, { once: true });
      document.addEventListener("load", scheduleInspection, true);
      document.addEventListener("loadeddata", scheduleInspection, true);
      document.addEventListener("canplay", scheduleInspection, true);
      const styleEvents = ["transitionstart", "transitionend", "animationstart", "animationend"];
      styleEvents.forEach(name => document.addEventListener(name, scheduleStyleInspection, true));
      function stopInspection() {
        stopped = true;
        if (frame != null) cancelAnimationFrame(frame);
        resizeObserver.disconnect();
        mutations.disconnect();
        document.removeEventListener("load", scheduleInspection, true);
        document.removeEventListener("loadeddata", scheduleInspection, true);
        document.removeEventListener("canplay", scheduleInspection, true);
        styleEvents.forEach(name => document.removeEventListener(name, scheduleStyleInspection, true));
      }
      window.addEventListener("pagehide", stopInspection, { once: true });
    }());
    </script>
    """

    private static func insertingInHead(_ content: String, into document: String) -> String {
        if let head = document.range(of: #"<head(?:\s[^>]*)?>"#, options: [.regularExpression, .caseInsensitive]) {
            var result = document
            result.insert(contentsOf: "\n" + content, at: head.upperBound)
            return result
        }
        if let doctype = document.range(of: #"<!doctype[^>]*>"#, options: [.regularExpression, .caseInsensitive]) {
            var result = document
            result.insert(contentsOf: "\n" + content, at: doctype.upperBound)
            return result
        }
        return content + "\n" + document
    }

    private static let hypertypeDependencyReference = PersistentJavaScriptLibrary.hypertypeReference

    static func requiredDependencies(in html: String, collectionId: String?) -> [PersistentArtworkDependency] {
        PersistentJavaScriptLibrary.requiredDependencies(in: html).filter {
            $0 != .hypertype || collectionId == PersistentArtworkDependency.hypertype.collectionId
        }
    }

    static func requiredDependency(in html: String, collectionId: String?) -> PersistentArtworkDependency? {
        requiredDependencies(in: html, collectionId: collectionId).first
    }

    static func resolveDependencies(
        in html: String,
        collectionId: String?,
        cache: PersistentArtworkDependencyCache
    ) async throws -> String {
        guard !requiredDependencies(in: html, collectionId: collectionId).isEmpty else { return html }
        return try await PersistentJavaScriptLibrary.resolve(html, cache: cache)
    }

    private static func persistentHypertypeDependency(_ script: Script) -> String {
        let cid = "QmXWXHGkxYFjJF5AuPiVB91VXK31LnoPN9EXKgiWFUvfT6"
        guard script.usesArtBlocksRenderer, script.kind == .svg,
              script.name == "Hypertype", script.chain == .ethereum,
              script.address == "0xbb5471c292065d3b01b2e81e299267221ae9a250", script.abId == "0",
              script.id == "0xbb5471c292065d3b01b2e81e299267221ae9a2500",
              let dependencies = script.externalAssetDependencies, dependencies.count == 1,
              let dependency = dependencies.first, dependency.index == 0,
              dependency.dependency_type == "IPFS", dependency.cid == cid,
              dependency.data == nil, dependency.bytecode_address == nil,
              SHA256.hash(data: Data(script.value.utf8)).map({ String(format: "%02x", $0) }).joined()
                == "d90c56c0fe5a34593123ad9ff81cb4da43981c1f182a70ca5e2b1be777955e51" else { return "" }
        return """
        (function nftPlayerHypertypePersistentDependency() {
          const prototype = HTMLScriptElement.prototype;
          const descriptor = Object.getOwnPropertyDescriptor(prototype, "src");
          const source = tokenData.preferredIPFSGateway + "\(cid)";
          Object.defineProperty(prototype, "src", Object.assign({}, descriptor, {
            set: function (value) {
              if (String(value) === source) {
                Object.defineProperty(prototype, "src", descriptor);
                return descriptor.set.call(this, "\(hypertypeDependencyReference)");
              }
              return descriptor.set.call(this, value);
            }
          }));
        }());
        """
    }

    private static func artBlocksTokenData(script: Script, token: BundledTokens.Item, hash: String) -> String {
        var value: [String: Any] = ["tokenId": token.id]
        if script.address.lowercased() == "0x059edd72cd353df5106d2b9cc5ab83a52287ac3a" {
            value["hashes"] = [hash]
        } else {
            value["hash"] = hash
        }
        value["preferredIPFSGateway"] = "https://gateway.pinata.cloud/ipfs/"
        value["preferredArweaveGateway"] = "https://arweave.net/"
        value["externalAssetDependencies"] = (script.externalAssetDependencies ?? []).map { dependency in
            var fields: [String: Any] = [
                "index": dependency.index,
                "cid": dependency.cid,
                "dependency_type": dependency.dependency_type
            ]
            let numericTypes = ["IPFS": 0, "ARWEAVE": 1, "ONCHAIN": 2, "ART_BLOCKS_DEPENDENCY_REGISTRY": 3]
            fields["dependencyType"] = numericTypes[dependency.dependency_type]
            if dependency.index == 0,
               dependency.dependency_type == "ONCHAIN",
               dependency.bytecode_address?.lowercased() == "0x00000000a78e278b2d2e2935faebe19ee9f1ff14",
               let parameters = token.contractParameters {
                fields["data"] = parameters
            } else if let data = dependency.data, data != "#web3call_contract#" {
                fields["data"] = data
            }
            if let address = dependency.bytecode_address {
                fields["bytecode_address"] = address
            }
            return fields
        }
        let data = try! JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])
        let json = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "<", with: "\\u003c")
        return "let tokenData = \(json);"
    }

    private static func moduleImportMap(script: Script, threeLibrary: String) -> String {
        var imports = ["three": moduleDataURL(threeLibrary)]
        if script.additionalLibraries?.contains(.tone1504) == true {
            imports["https://cdnjs.cloudflare.com/ajax/libs/tone/15.0.4/Tone.min.js"] = moduleDataURL("export default window.Tone;")
        }
        let data = try! JSONSerialization.data(withJSONObject: ["imports": imports], options: [.sortedKeys, .withoutEscapingSlashes])
        return "<script type=\"importmap\">\(String(decoding: data, as: UTF8.self))</script>"
    }

    private static func escapedInlineLibrary(_ source: String) -> String {
        if let library = PersistentJavaScriptLibrary.all.first(where: { PersistentJavaScriptLibrary.reference(for: $0) == source }) {
            return PersistentJavaScriptLibrary.reference(for: library, format: .escapedInline)
        }
        return source.replacingOccurrences(of: "</script", with: "<\\/script")
    }

    private static func moduleDataURL(_ source: String) -> String {
        if let reference = PersistentJavaScriptLibrary.dataURLReference(forInlineReference: source) { return reference }
        return "data:text/javascript;base64," + Data(source.utf8).base64EncodedString()
    }

    private static func artworkErrorBootstrap(
        collectionId: String,
        tokenId: String,
        measuresProcessingSampling: Bool = false,
        frameDrivenPresentation: Bool = false
    ) -> String {
        let identityData = try! JSONSerialization.data(withJSONObject: [
            "collectionId": collectionId,
            "tokenId": tokenId
        ], options: [.sortedKeys])
        let identity = String(decoding: identityData, as: UTF8.self)
            .replacingOccurrences(of: "<", with: "\\u003c")
        let bootstrap = """
        <script>
        (function () {
          const identity = \(identity);
          const generation = window.__artBlocksPreviewGeneration || null;
          const measuresProcessingSampling = \(measuresProcessingSampling ? "true" : "false");
          function post(handlerName, fields) {
            const handler = window.webkit && window.webkit.messageHandlers
              && window.webkit.messageHandlers[handlerName];
            if (handler) handler.postMessage(Object.assign({ generation: generation }, identity, fields));
          }
          window.showPreviewError = function (message) {
            message = String(message || "The artwork could not be rendered.");
            console.error("Art Blocks preview", identity.collectionId, identity.tokenId, message);
            post("artBlocksPreviewError", { message: message });
          };
          const assetRecords = new WeakMap();
          const pendingAssets = new Set();
          let pageIsHidden = false;
          function reportRequestFailure(source, error) {
            if (pageIsHidden || error && error.name === "AbortError") return;
            const detail = error ? ": " + String(error.message || error) : "";
            window.showPreviewError("Could not load artwork asset: " + String(source) + detail);
          }
          function watchRequest(source) {
            if (pageIsHidden) return function () {};
            let url;
            try { url = new URL(String(source), document.baseURI); } catch (_) { return function () {}; }
            if (url.protocol !== "https:" && url.protocol !== "http:") return function () {};
            let timer;
            const record = { finish: function () {
              clearTimeout(timer);
              pendingAssets.delete(record);
            } };
            pendingAssets.add(record);
            timer = setTimeout(function () {
              record.finish();
              window.showPreviewError("Timed out loading artwork asset: " + url.href);
            }, 60000);
            return record.finish;
          }
          const watchedResponses = new WeakSet();
          function watchResponse(response, source) {
            if (watchedResponses.has(response)) return response;
            watchedResponses.add(response);
            ["arrayBuffer", "blob", "bytes", "formData", "json", "text"].forEach(function (name) {
              const consume = response[name];
              if (typeof consume !== "function") return;
              try { Object.defineProperty(response, name, { configurable: true, writable: true, value: function () {
                const finish = watchRequest(source);
                try {
                  return consume.apply(this, arguments).then(function (body) {
                    finish();
                    return body;
                  }, function (error) {
                    finish();
                    reportRequestFailure(source, error);
                    throw error;
                  });
                } catch (error) {
                  finish();
                  reportRequestFailure(source, error);
                  throw error;
                }
              } }); } catch (_) {}
            });
            const clone = response.clone;
            try { Object.defineProperty(response, "clone", { configurable: true, writable: true, value: function () {
              return watchResponse(clone.apply(this, arguments), source);
            } }); } catch (_) {}
            return response;
          }
          const fetch = window.fetch;
          window.fetch = function (input, options) {
            const source = input && input.url || input;
            const finish = watchRequest(source);
            try {
              return fetch.call(this, input, options).then(function (response) {
                finish();
                if (response.status >= 400) {
                  reportRequestFailure(response.url || source, "HTTP " + response.status);
                }
                return watchResponse(response, source);
              }, function (error) {
                finish();
                reportRequestFailure(source, error);
                throw error;
              });
            } catch (error) {
              finish();
              reportRequestFailure(source, error);
              throw error;
            }
          };
          const xhrSources = new WeakMap();
          const open = XMLHttpRequest.prototype.open;
          const send = XMLHttpRequest.prototype.send;
          XMLHttpRequest.prototype.open = function (method, source) {
            xhrSources.set(this, source);
            return open.apply(this, arguments);
          };
          XMLHttpRequest.prototype.send = function () {
            const finish = watchRequest(xhrSources.get(this));
            this.addEventListener("loadend", finish, { once: true });
            try { return send.apply(this, arguments); } catch (error) {
              finish();
              throw error;
            }
          };
          function watchAsset(element, source, restart) {
            const previous = assetRecords.get(element);
            function stopPrevious() {
              if (previous) previous.finish();
              assetRecords.delete(element);
            }
            let url;
            try { url = new URL(String(source), document.baseURI); } catch (_) { stopPrevious(); return; }
            if (url.protocol !== "https:" && url.protocol !== "http:") { stopPrevious(); return; }
            if (previous && previous.url === url.href && !restart) return;
            if (previous) previous.finish();
            const record = { url: url.href, finish: null };
            let timer;
            function finish() {
              clearTimeout(timer);
              element.removeEventListener("load", finish);
              element.removeEventListener("error", fail);
              pendingAssets.delete(record);
            }
            function fail() {
              finish();
              window.showPreviewError("Could not load artwork asset: " + record.url);
            }
            record.finish = finish;
            assetRecords.set(element, record);
            pendingAssets.add(record);
            element.addEventListener("load", finish);
            element.addEventListener("error", fail);
            timer = setTimeout(function () {
              finish();
              window.showPreviewError("Timed out loading artwork asset: " + record.url);
            }, 60000);
            if (!restart && element.tagName === "IMG" && element.complete && element.naturalWidth > 0) finish();
          }
          [HTMLImageElement.prototype, HTMLScriptElement.prototype].forEach(function (prototype) {
            const descriptor = Object.getOwnPropertyDescriptor(prototype, "src");
            if (!descriptor || !descriptor.set || !descriptor.configurable) return;
            Object.defineProperty(prototype, "src", {
              configurable: descriptor.configurable,
              enumerable: descriptor.enumerable,
              get: descriptor.get,
              set: function (value) {
                watchAsset(this, value, true);
                try { descriptor.set.call(this, value); } catch (error) {
                  const record = assetRecords.get(this);
                  if (record) record.finish();
                  throw error;
                }
              }
            });
          });
          function discoverAssets(node) {
            if (node.nodeType !== 1) return;
            if (node.matches("img[src],script[src]")) watchAsset(node, node.getAttribute("src"), false);
            node.querySelectorAll("img[src],script[src]").forEach(function (element) {
              watchAsset(element, element.getAttribute("src"), false);
            });
          }
          const assetObserver = new MutationObserver(function (mutations) {
            mutations.forEach(function (mutation) {
              if (mutation.type === "attributes") discoverAssets(mutation.target);
              else mutation.addedNodes.forEach(discoverAssets);
            });
          });
          assetObserver.observe(document, { subtree: true, childList: true, attributes: true, attributeFilter: ["src"] });
          window.addEventListener("pagehide", function () {
            pageIsHidden = true;
            assetObserver.disconnect();
            pendingAssets.forEach(function (record) { record.finish(); });
          }, { once: true });
          window.addEventListener("error", function (event) {
            const target = event.target;
            if (target && assetRecords.has(target)) return;
            const source = target && (target.currentSrc || target.src || target.href);
            window.showPreviewError(event.message || (source ? "Could not load " + source : "Artwork script failed."));
          }, true);
          window.addEventListener("unhandledrejection", function (event) {
            const reason = event.reason;
            window.showPreviewError(reason && reason.message || reason || "Artwork promise failed.");
          });
          document.addEventListener("DOMContentLoaded", function () {
            post("artBlocksPreviewReady", {});
          }, { once: true });
          let resolutionTimer;
          let previousResolution;
          let reportedResolution;
          const renderedCanvases = new WeakSet();
          const observedContexts = new WeakSet();
          const canvasWidth = Object.getOwnPropertyDescriptor(HTMLCanvasElement.prototype, "width").get;
          const canvasHeight = Object.getOwnPropertyDescriptor(HTMLCanvasElement.prototype, "height").get;
          const canvasGetContext = HTMLCanvasElement.prototype.getContext;
          function observeDrawing(canvas, context, kind) {
            if (observedContexts.has(context)) return;
            observedContexts.add(context);
            const methods = kind === "2d"
              ? ["fill", "stroke", "fillRect", "strokeRect", "drawImage", "putImageData", "fillText", "strokeText"]
              : ["drawArrays", "drawElements", "drawArraysInstanced", "drawElementsInstanced"];
            const originals = new Map();
            methods.forEach(function (name) {
              const original = context[name];
              if (typeof original !== "function") return;
              const descriptor = Object.getOwnPropertyDescriptor(context, name);
              try {
                Object.defineProperty(context, name, { configurable: true, writable: true, value: function () {
                  renderedCanvases.add(canvas);
                  originals.forEach(function (entry, method) {
                    if (entry.descriptor) Object.defineProperty(context, method, entry.descriptor);
                    else delete context[method];
                  });
                  originals.clear();
                  return original.apply(this, arguments);
                } });
                originals.set(name, { descriptor: descriptor });
              } catch (_) {}
            });
          }
          HTMLCanvasElement.prototype.getContext = function () {
            const context = canvasGetContext.apply(this, arguments);
            if (context) observeDrawing(this, context, arguments[0]);
            return context;
          };
          const transferCanvas = HTMLCanvasElement.prototype.transferControlToOffscreen;
          if (typeof transferCanvas === "function") {
            HTMLCanvasElement.prototype.transferControlToOffscreen = function () {
              const canvas = transferCanvas.apply(this, arguments);
              renderedCanvases.add(this);
              return canvas;
            };
          }
          function inspectResolution() {
            if (pageIsHidden) return;
            const visualViewport = window.visualViewport;
            const viewportWidth = window.innerWidth, viewportHeight = window.innerHeight;
            const viewportScale = visualViewport ? visualViewport.scale : 1;
            if (!(viewportWidth > 0 && viewportHeight > 0)) return;
            const canvases = [];
            document.querySelectorAll("canvas").forEach(function (canvas, index) {
              if (!renderedCanvases.has(canvas)) return;
              const rect = canvas.getBoundingClientRect();
              const bitmapWidth = canvasWidth.call(canvas), bitmapHeight = canvasHeight.call(canvas);
              if (!(bitmapWidth > 0 && bitmapHeight > 0 && rect.width > 0 && rect.height > 0)) return;
              let element = canvas;
              let preservesSampling = false;
              while (element) {
                const style = getComputedStyle(element);
                if (style.display === "none" || style.visibility === "hidden" || Number(style.opacity) === 0) return;
                const blur = style.filter.match(/blur\\(\\s*([\\d.]+)px\\s*\\)/);
                if ((!measuresProcessingSampling && (style.imageRendering === "pixelated" || style.imageRendering === "crisp-edges"))
                    || (blur && Number(blur[1]) > 0)) preservesSampling = true;
                element = element.parentElement;
              }
              const visibleWidth = Math.max(0, Math.min(rect.right, viewportWidth) - Math.max(rect.left, 0));
              const visibleHeight = Math.max(0, Math.min(rect.bottom, viewportHeight) - Math.max(rect.top, 0));
              const area = visibleWidth * visibleHeight;
              if (area > 0) canvases.push({canvas: canvas, key: canvas.id ? "id:" + canvas.id : "canvas:" + index, bitmapWidth: bitmapWidth, bitmapHeight: bitmapHeight,
                rect: rect, area: area, preservesSampling: preservesSampling});
            });
            if (!canvases.length) return;
            const surfaces = canvases.filter(function (entry) { return !entry.preservesSampling; });
            if (!surfaces.length) return;
            const density = Math.max(0.01, (Number(window.devicePixelRatio) || 1) * viewportScale);
            const signature = surfaces.map(function (entry) {
              return [entry.key, entry.bitmapWidth, entry.bitmapHeight, entry.rect.width, entry.rect.height, entry.rect.x, entry.rect.y].join(":");
            }).join("|") + ":" + density;
            if (signature !== previousResolution) {
              previousResolution = signature;
              return;
            }
            if (signature === reportedResolution) return;
            let factor = 0;
            let measured = surfaces[0];
            surfaces.forEach(function (entry) {
              const needed = Math.max(entry.rect.width * density / entry.bitmapWidth,
                entry.rect.height * density / entry.bitmapHeight);
              if (needed > factor) {
                factor = needed;
                measured = entry;
              }
            });
            window.__artBlocksPreviewResolution = {
              factor: factor, canvasWidth: measured.bitmapWidth, canvasHeight: measured.bitmapHeight,
              cssWidth: measured.rect.width, cssHeight: measured.rect.height, viewportScale: viewportScale,
              measuredSurfaceKey: measured.key, preservedSamplingSurfaces: canvases.length - surfaces.length,
              surfaces: surfaces.map(function (entry) {
                return { key: entry.key, canvasWidth: entry.bitmapWidth, canvasHeight: entry.bitmapHeight,
                  cssWidth: entry.rect.width, cssHeight: entry.rect.height };
              })
            };
            reportedResolution = signature;
            post("artBlocksPreviewResolution", window.__artBlocksPreviewResolution);
          }
          function scheduleResolutionInspection() {
            inspectResolution();
            if (!pageIsHidden) resolutionTimer = setTimeout(scheduleResolutionInspection, reportedResolution ? 1000 : 250);
          }
          document.addEventListener("DOMContentLoaded", function () {
            scheduleResolutionInspection();
          }, { once: true });
          window.addEventListener("pagehide", function () { clearTimeout(resolutionTimer); }, { once: true });
        }());
        </script>
        """
        guard frameDrivenPresentation else { return bootstrap }
        return bootstrap.replacingOccurrences(
            of: "function scheduleResolutionInspection() {",
            with: "window.addEventListener(\"artBlocksPreviewInspectResolution\", inspectResolution);\n          function scheduleResolutionInspection() {"
        )
    }
    
}
