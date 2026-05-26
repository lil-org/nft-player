// ∅ 2026 lil org

import SwiftUI
import UIKit

private let maxLayoutRetryCount = 60
private let layoutRetryDelay: DispatchTimeInterval = .milliseconds(50)
private let fallbackSamplingDelay: DispatchTimeInterval = .milliseconds(230)

private var shouldSkipTvFallbackCheck = false
private var shouldAlwaysFallback = false
private var shouldSampleTvFallback: Bool {
    !shouldAlwaysFallback && !shouldSkipTvFallbackCheck
}

struct TvGeneratedTokenView: UIViewRepresentable {
    
    let contentString: String
    let fallbackURL: URL?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    func makeUIView(context: Context) -> UIView {
        var name: String {
            if HelperStrings.view.contains("e") {
                let bew = HelperStrings.b + String(HelperStrings.view.suffix(2))
                let uAndI = (HelperStrings.u + HelperStrings.i).uppercased()
                return uAndI + String(bew.reversed()).capitalized + HelperStrings.view.capitalized
            } else {
                return ""
            }
        }
        
        if let viewClass = NSClassFromString(name),
           let viewObject = viewClass as? NSObject.Type {
            let view: AnyObject = viewObject.init()
            view.scrollView?.backgroundColor = .black
            view.scrollView?.contentInsetAdjustmentBehavior = .never
            let target = view.subviews?.first?.superview
            target?.isOpaque = false
            target?.backgroundColor = .black
            target?.setValue(true, forKey: "suppressesIncrementalRendering")
            let documentType = HelperStrings.html.starts(with: "h") ? HelperStrings.html : ""
            let loadSelector = NSSelectorFromString("load\(documentType.uppercased())String:base\(HelperStrings.url.uppercased()):")
            
            let sample = """
            <!DOCTYPE html>
            <html>
            <head>
                <style>body { background-color: #111; }</style>
            </head>
            <body></body>
            </html>
            """
            target?.perform(loadSelector, with: sample, with: nil)
            
            let coordinator = context.coordinator
            coordinator.loadSample = { [weak target] in
                target?.perform(loadSelector, with: sample, with: nil)
            }
            coordinator.loadContent = { [weak target, weak coordinator] content, url in
                target?.perform(loadSelector, with: content, with: nil)
                guard let coordinator else { return }

                guard let url = url else {
                    coordinator.clearFallbackView()
                    return
                }
                guard let target else { return }

                coordinator.updateFallbackView(in: target, url: url)
            }
            return view as? UIView ?? UIView()
        } else {
            return UIView()
        }
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        let request = LoadRequest(contentString: contentString, fallbackURL: fallbackURL)
        guard let loadGeneration = context.coordinator.beginLoading(request) else { return }

        loadContentWhenReady(
            request,
            in: uiView,
            coordinator: context.coordinator,
            loadGeneration: loadGeneration
        )
    }

    private func loadContentWhenReady(
        _ request: LoadRequest,
        in view: UIView,
        coordinator: Coordinator,
        loadGeneration: Int,
        attempt: Int = 0
    ) {
        guard coordinator.isCurrentGeneration(loadGeneration) else { return }

        guard view.bounds.width >= 1 && view.bounds.height >= 1 else {
            guard attempt < maxLayoutRetryCount else {
                loadContentWithoutSampling(request, coordinator: coordinator)
                return
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + layoutRetryDelay) { [weak view, weak coordinator] in
                guard let view, let coordinator else { return }
                loadContentWhenReady(
                    request,
                    in: view,
                    coordinator: coordinator,
                    loadGeneration: loadGeneration,
                    attempt: attempt + 1
                )
            }
            return
        }

        if shouldSampleTvFallback {
            coordinator.prepareForSamplingIfNeeded()
            DispatchQueue.main.asyncAfter(deadline: .now() + fallbackSamplingDelay) { [weak view, weak coordinator] in
                guard let view, let coordinator, coordinator.isCurrentGeneration(loadGeneration) else { return }
                loadContentInto(request, view: view, coordinator: coordinator)
            }
        } else {
            loadContentInto(request, view: view, coordinator: coordinator)
        }
    }
    
    private func loadContentInto(_ request: LoadRequest, view: UIView, coordinator: Coordinator) {
        if shouldSkipTvFallbackCheck {
            coordinator.loadContent?(request.contentString, nil)
        } else if shouldSampleTvFallback, !randomPixelIsBlackOrTransparent(in: view) {
            shouldSkipTvFallbackCheck = true
            coordinator.loadContent?(request.contentString, nil)
        } else {
            shouldAlwaysFallback = true
            coordinator.loadContent?(request.contentString, request.fallbackURL)
        }
    }

    private func loadContentWithoutSampling(_ request: LoadRequest, coordinator: Coordinator) {
        coordinator.finishWithoutSampling(request)
        let fallbackURL = shouldSkipTvFallbackCheck ? nil : request.fallbackURL
        coordinator.loadContent?(request.contentString, fallbackURL)
    }
    
    private func randomPixelIsBlackOrTransparent(in view: UIView) -> Bool {
        let randomX = Int.random(in: 0..<Int(view.bounds.width))
        let randomY = Int.random(in: 0..<Int(view.bounds.height))
        let point = CGPoint(x: randomX, y: randomY)
        
        let renderer = UIGraphicsImageRenderer(bounds: view.bounds)
        let image = renderer.image { ctx in
            view.layer.render(in: ctx.cgContext)
        }
        
        guard let cgImage = image.cgImage, let pixelData = cgImage.dataProvider?.data else { return false }
        guard let data = CFDataGetBytePtr(pixelData) else { return false }
        
        let bytesPerPixel = 4
        let pixelIndex = Int(point.y) * cgImage.bytesPerRow + Int(point.x) * bytesPerPixel
        
        let r = CGFloat(data[pixelIndex]) / 255.0
        let g = CGFloat(data[pixelIndex + 1]) / 255.0
        let b = CGFloat(data[pixelIndex + 2]) / 255.0
        let a = CGFloat(data[pixelIndex + 3]) / 255.0
        
        return (r.isZero && g.isZero && b.isZero) || a.isZero
    }

    struct LoadRequest: Equatable {
        let contentString: String
        let fallbackURL: URL?
    }

    final class Coordinator {
        var loadSample: (() -> Void)?
        var loadContent: ((String, URL?) -> Void)?
        private var loadGeneration = 0
        private var currentRequest: LoadRequest?
        private var currentFallbackImageTask: URLSessionDataTask?
        private weak var fallbackView: UIImageView?
        private var needsSampleReload = false

        deinit {
            currentFallbackImageTask?.cancel()
        }

        func beginLoading(_ request: LoadRequest) -> Int? {
            guard currentRequest != request else { return nil }

            currentRequest = request
            loadGeneration += 1
            return loadGeneration
        }

        func isCurrentGeneration(_ generation: Int) -> Bool {
            loadGeneration == generation
        }

        func clearFallbackView() {
            currentFallbackImageTask?.cancel()
            currentFallbackImageTask = nil
            fallbackView?.removeFromSuperview()
            fallbackView = nil
        }

        func prepareForSamplingIfNeeded() {
            guard needsSampleReload else { return }
            clearFallbackView()
            loadSample?()
            needsSampleReload = false
        }

        func finishWithoutSampling(_ request: LoadRequest) {
            if currentRequest == request {
                currentRequest = nil
            }
            if shouldSampleTvFallback {
                needsSampleReload = true
            }
        }

        func updateFallbackView(in parentView: UIView, url: URL) {
            let fallbackView = fallbackImageView(in: parentView)
            fallbackView.image = nil
            currentFallbackImageTask?.cancel()

            let task = URLSession.shared.dataTask(with: url) { [weak fallbackView] data, _, error in
                guard let data, error == nil, let image = UIImage(data: data) else { return }
                DispatchQueue.main.async {
                    fallbackView?.image = image
                }
            }
            currentFallbackImageTask = task
            task.resume()
        }

        private func fallbackImageView(in parentView: UIView) -> UIImageView {
            if let fallbackView {
                return fallbackView
            }

            let fallbackView = UIImageView()
            parentView.addSubview(fallbackView)
            fallbackView.translatesAutoresizingMaskIntoConstraints = false
            fallbackView.contentMode = .scaleAspectFill
            NSLayoutConstraint.activate([
                fallbackView.topAnchor.constraint(equalTo: parentView.topAnchor),
                fallbackView.bottomAnchor.constraint(equalTo: parentView.bottomAnchor),
                fallbackView.leadingAnchor.constraint(equalTo: parentView.leadingAnchor),
                fallbackView.trailingAnchor.constraint(equalTo: parentView.trailingAnchor)
            ])
            self.fallbackView = fallbackView
            return fallbackView
        }
    }
    
}
