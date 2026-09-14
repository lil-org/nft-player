nonisolated enum ArtBlocksRenderingResolutionOverrides {
    static func usesProcessingRetinaCanvas(_ script: Script) -> Bool {
        guard script.usesArtBlocksRenderer, script.kind == .processingjs146 else { return false }
        return (script.id == "0x059edd72cd353df5106d2b9cc5ab83a52287ac3a1" && script.name == "Genesis")
            || (script.id == "0x059edd72cd353df5106d2b9cc5ab83a52287ac3a2" && script.name == "Construction Token")
    }

    static func beforeArtist(_ script: Script) -> String {
        if usesProcessingRetinaCanvas(script) { return processingRetinaCanvas }
        if snapshotProfile(script) == "murano" {
            return highResolutionSnapshots("""
            p5.prototype.registerMethod("init", function () {
              const instance = this;
              const createGraphics = instance.createGraphics;
              instance.createGraphics = function () {
                const graphics = createGraphics.apply(instance, arguments);
                const originalGet = graphics.get;
                graphics.get = function () {
                  if (arguments.length === 0 && graphics.width === instance.width
                      && graphics.height === instance.height) {
                    const result = denseImage(graphics, 0, 0, graphics.width, graphics.height);
                    if (result) return result;
                  }
                  return originalGet.apply(graphics, arguments);
                };
                return graphics;
              };
            });
            """)
        }
        guard script.usesArtBlocksRenderer,
              script.id == "0x99a9b7c1116f9ceeb1652de04d5969cce509b069488",
              script.name == "Växt",
              script.kind == .js else { return "" }
        return """
        (function () {
          const query = new URLSearchParams(window.location.search).toString();
          const get = URLSearchParams.prototype.get;
          URLSearchParams.prototype.get = function (name) {
            const value = get.call(this, name);
            if (name !== "pr" || this.toString() !== query) return value;
            URLSearchParams.prototype.get = get;
            const nativeDensity = Number(window.devicePixelRatio);
            const requestedDensity = Number(value);
            return String(Math.max(
              2,
              Number.isFinite(nativeDensity) ? nativeDensity : 1,
              Number.isFinite(requestedDensity) ? requestedDensity : 0
            ));
          };
        }());
        """
    }

    static func afterArtist(_ script: Script) -> String {
        if let profile = snapshotProfile(script), profile != "murano" {
            let replacement: String
            switch profile {
            case "bauhaus":
                replacement = """
                draw = wrapRender(draw, function (args, source) {
                  return args.length === 4 && args[0] === 25 && args[1] === 25
                    && args[2] === source.width - 50 && args[3] === source.height - 50;
                });
                """
            case "fields":
                replacement = """
                applyEffectsToFields = wrapRender(applyEffectsToFields, function (args, source) {
                  const width = source.width / numFields, height = source.height / numFields;
                  return args.length === 4 && ((args[2] === width && args[3] === height / 2)
                    || (args[2] === width / 2 && args[3] === height));
                });
                """
            default:
                replacement = "draw = wrapRender(draw, function (args) { return args.length === 0; });"
            }
            return highResolutionSnapshots(replacement)
        }
        if script.usesArtBlocksRenderer,
           script.id == "0x0a1bbd57033f57e7b6743621b79fcb9eb2ce367629",
           script.name == "100 Sunsets", script.kind == .p5js100,
           script.value.contains("density=2,pixelDensity(density)"), script.value.contains("function changeResWebgl(e)") {
            return """
            (function () {
              if (typeof draw !== "function" || typeof changeRes !== "function") throw new Error("100 Sunsets resolution controls are unavailable.");
              const original = draw;
              draw = function () {
                draw = original;
                const result = original.apply(this, arguments);
                const current = pixelDensity();
                const native = Number(window.devicePixelRatio) * (window.visualViewport ? window.visualViewport.scale : 1);
                if (useGL && Number.isFinite(native) && native > current) changeRes(Math.max(current, Math.ceil(native)), true);
                return result;
              };
            }());
            """
        }
        if script.usesArtBlocksRenderer,
           script.id == "0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd27062",
           script.name == "Bubble Blobby", script.kind == .regl,
           script.value.contains("c=a.get(\"q\")||3,f=[1,1.5,2,2.5,3]"), script.value.contains("V||(30==t") {
            return """
            (function () {
              if (typeof p !== "function" || typeof V !== "boolean") throw new Error("Bubble Blobby quality controls are unavailable.");
              V = true;
              p(1);
            }());
            """
        }
        if let replacement = compositingReplacement(script) {
            return highResolutionCompositing(replacement)
        }
        guard script.usesArtBlocksRenderer,
              script.id == "0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270340",
              script.name == "Vahria",
              script.kind == .three else { return "" }
        return """
        (function () {
          if (typeof renderer === "undefined" || typeof composer === "undefined"
              || typeof displacementShader === "undefined" || typeof displacementPass === "undefined"
              || typeof render !== "function" || !displacementShader.uniforms.ja
              || !displacementPass.uniforms.ja) {
            throw new Error("Vahria's resolution controls are unavailable.");
          }
          const originalRender = render;
          const logicalSize = new THREE.Vector2();
          const drawingSize = new THREE.Vector2();
          function synchronizeResolution() {
            const nativeDensity = Number(window.devicePixelRatio);
            const density = Math.max(
              renderer.getPixelRatio(),
              Number.isFinite(nativeDensity) ? nativeDensity : 1
            );
            if (renderer.getPixelRatio() !== density) renderer.setPixelRatio(density);
            renderer.getSize(logicalSize);
            renderer.getDrawingBufferSize(drawingSize);
            if (composer._width !== logicalSize.x || composer._height !== logicalSize.y) {
              composer.setSize(logicalSize.x, logicalSize.y);
            }
            if (composer._pixelRatio !== density) composer.setPixelRatio(density);
            displacementShader.uniforms.ja.value = [drawingSize.x, drawingSize.y];
            displacementPass.uniforms.ja.value = [drawingSize.x, drawingSize.y];
          }
          render = function () {
            synchronizeResolution();
            return originalRender.apply(this, arguments);
          };
          \(ArtBlocksRenderingStartupProfiles.startupProfile(script) == nil ? "render();" : "synchronizeResolution();")
        }());
        """
    }

    private static func snapshotProfile(_ script: Script) -> String? {
        guard script.usesArtBlocksRenderer, script.kind == .p5js100 else { return nil }
        switch (script.id, script.name) {
        case ("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270193", "Murano Fantasy"):
            return script.value.contains("Le=b.get(),He(d)")
                && script.value.contains("Ge.copy(Le,0,0,2*e,2*a,0,0,2*e,2*a)") ? "murano" : nil
        case ("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270271", "Time travel in a subconscious mind"):
            return script.value.contains("C1=get(),ST--") && script.value.contains("C2=get(),Cu") ? "time" : nil
        case ("0x47a91457a3a1f700097199fd63c039c4784384ab278", "Bauhaus Synthesis"):
            return script.value.contains("img = get(25,25,width-50,height-50);")
                && script.value.contains("image(img, width/2 - (width/1.5)/2") ? "bauhaus" : nil
        case ("0x47a91457a3a1f700097199fd63c039c4784384ab315", "Can you see it"):
            return script.value.contains("function applyEffectsToFields()")
                && script.value.contains("image(get(x, y, w, h /2), 0, -h / 2);")
                && script.value.contains("image(get(x, y, w / 2, h), -w / 2, 0);") ? "fields" : nil
        default:
            return nil
        }
    }

    private static func highResolutionSnapshots(_ replacement: String) -> String {
        """
        (function () {
          const canvasWidth = Object.getOwnPropertyDescriptor(HTMLCanvasElement.prototype, "width").get;
          const canvasHeight = Object.getOwnPropertyDescriptor(HTMLCanvasElement.prototype, "height").get;
          function denseImage(source, x, y, width, height) {
            if (!source || !(source.canvas instanceof HTMLCanvasElement)) return null;
            const density = Number(source._pixelDensity);
            const sourceWidth = Number(source.width), sourceHeight = Number(source.height);
            if (![density, sourceWidth, sourceHeight, x, y, width, height].every(Number.isFinite)
                || density <= 1 || sourceWidth <= 0 || sourceHeight <= 0 || width <= 0 || height <= 0
                || x < 0 || y < 0) return null;
            const bitmapWidth = canvasWidth.call(source.canvas), bitmapHeight = canvasHeight.call(source.canvas);
            const imageWidth = Math.floor(width * density), imageHeight = Math.floor(height * density);
            if (bitmapWidth <= 0 || bitmapHeight <= 0 || imageWidth <= 0 || imageHeight <= 0
                || Math.abs(bitmapWidth - sourceWidth * density) > 1
                || Math.abs(bitmapHeight - sourceHeight * density) > 1) return null;
            const result = new p5.Image(width, height);
            result.canvas.width = imageWidth;
            result.canvas.height = imageHeight;
            result._pixelDensity = density;
            result.drawingContext.drawImage(source.canvas, x * density, y * density,
              width * density, height * density, 0, 0, imageWidth, imageHeight);
            result.setModified(true);
            return result;
          }
          function wrapRender(original, accepts) {
            return function () {
              const source = p5.instance;
              const renderer = source && source._renderer;
              if (!renderer) return original.apply(this, arguments);
              const descriptor = Object.getOwnPropertyDescriptor(renderer, "get");
              const originalGet = renderer.get;
              renderer.get = function (x, y, width, height) {
                if (accepts(arguments, source)) {
                  const result = arguments.length === 0
                    ? denseImage(source, 0, 0, source.width, source.height)
                    : denseImage(source, x, y, width, height);
                  if (result) return result;
                }
                return originalGet.apply(this, arguments);
              };
              try { return original.apply(this, arguments); }
              finally {
                if (descriptor) Object.defineProperty(renderer, "get", descriptor);
                else delete renderer.get;
              }
            };
          }
          \(replacement)
        }());
        """
    }

    private static func compositingReplacement(_ script: Script) -> String? {
        guard script.usesArtBlocksRenderer, script.kind == .p5js100 else { return nil }
        switch (script.id, script.name) {
        case ("0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd27063", "Ode to Roy"):
            guard script.value.contains("(im = ov.get()).mask(ma), image(im, -cn, -cn)") else { return nil }
            return """
            if (typeof oP !== "function") throw new Error("Ode to Roy's mask function is unavailable.");
            const original = oP;
            oP = function () {
              const result = maskedImage(ov, ma);
              if (!result) return original.apply(this, arguments);
              im = result;
              return image(im, -cn, -cn, ov.width, ov.height);
            };
            """
        default:
            return nil
        }
    }

    private static func highResolutionCompositing(_ replacement: String) -> String {
        """
        (function () {
          const canvasWidth = Object.getOwnPropertyDescriptor(HTMLCanvasElement.prototype, "width").get;
          const canvasHeight = Object.getOwnPropertyDescriptor(HTMLCanvasElement.prototype, "height").get;
          function maskedImage(source, mask) {
            if (!source || !mask || !(source.canvas instanceof HTMLCanvasElement)
                || !(mask.canvas instanceof HTMLCanvasElement)) return null;
            const width = canvasWidth.call(source.canvas), height = canvasHeight.call(source.canvas);
            const maskWidth = canvasWidth.call(mask.canvas), maskHeight = canvasHeight.call(mask.canvas);
            if (!(width > 0 && height > 0 && maskWidth > 0 && maskHeight > 0
                && source.width > 0 && source.height > 0)) return null;
            if (width <= source.width && height <= source.height) return null;
            const result = new p5.Image(width, height);
            const context = result.drawingContext;
            context.drawImage(source.canvas, 0, 0, width, height, 0, 0, width, height);
            context.globalCompositeOperation = "destination-in";
            context.drawImage(mask.canvas, 0, 0, maskWidth, maskHeight, 0, 0, width, height);
            context.globalCompositeOperation = "source-over";
            result.setModified(true);
            return result;
          }
          \(replacement)
        }());
        """
    }

    private static let processingRetinaCanvas = """
    (function () {
      const density = Math.max(1, Number(window.devicePixelRatio) || 1);
      if (density <= 1) return;
      const states = new WeakMap();
      const prototype = HTMLCanvasElement.prototype;
      const width = Object.getOwnPropertyDescriptor(prototype, "width");
      const height = Object.getOwnPropertyDescriptor(prototype, "height");
      const getContext = prototype.getContext;
      const setTransform = CanvasRenderingContext2D.prototype.setTransform;
      function restoreBase(state) {
        setTransform.call(state.context, density, 0, 0, density, 0, 0);
      }
      function setDimension(canvas, axis, descriptor, value) {
        const state = states.get(canvas);
        descriptor.set.call(canvas, value);
        if (!state) return;
        state[axis] = descriptor.get.call(canvas);
        descriptor.set.call(canvas, Math.round(state[axis] * density));
        canvas.style.width = state.width + "px";
        canvas.style.height = state.height + "px";
        restoreBase(state);
      }
      Object.defineProperty(prototype, "width", {
        configurable: width.configurable, enumerable: width.enumerable,
        get: function () { return states.has(this) ? states.get(this).width : width.get.call(this); },
        set: function (value) { setDimension(this, "width", width, value); }
      });
      Object.defineProperty(prototype, "height", {
        configurable: height.configurable, enumerable: height.enumerable,
        get: function () { return states.has(this) ? states.get(this).height : height.get.call(this); },
        set: function (value) { setDimension(this, "height", height, value); }
      });
      prototype.getContext = function (kind) {
        const context = getContext.apply(this, arguments);
        if (kind !== "2d" || !context || states.has(this) || !this.isConnected) return context;
        const state = { width: width.get.call(this), height: height.get.call(this), context: context };
        states.set(this, state);
        width.set.call(this, Math.round(state.width * density));
        height.set.call(this, Math.round(state.height * density));
        this.style.width = state.width + "px";
        this.style.height = state.height + "px";
        Object.defineProperty(context, "setTransform", {
          configurable: true, writable: true,
          value: function () {
            if (arguments.length === 0) return setTransform.call(this, density, 0, 0, density, 0, 0);
            if (arguments.length === 1) {
              const matrix = DOMMatrix.fromMatrix(arguments[0]);
              return setTransform.call(this, matrix.a * density, matrix.b * density,
                matrix.c * density, matrix.d * density, matrix.e * density, matrix.f * density);
            }
            if (arguments.length < 6) return setTransform.apply(this, arguments);
            return setTransform.call(this, arguments[0] * density, arguments[1] * density,
              arguments[2] * density, arguments[3] * density, arguments[4] * density, arguments[5] * density);
          }
        });
        Object.defineProperty(context, "resetTransform", {
          configurable: true, writable: true,
          value: function () { return setTransform.call(this, density, 0, 0, density, 0, 0); }
        });
        restoreBase(state);
        return context;
      };
    }());
    """
}
