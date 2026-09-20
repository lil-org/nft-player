// ∅ 2026 lil org

import UIKit
import WebKit

fileprivate weak var currentDisplay: ExternalDisplayViewController?
fileprivate var currentToken = GeneratedToken.empty

func updateExternalDisplayToken(_ token: GeneratedToken) {
    currentToken = token
    currentDisplay?.renderCurrentItem()
}

class ExternalDisplayViewController: UIViewController {
    
    private let artworkDependencyCache: PersistentArtworkDependencyCache
    private let mediaCache: DownloadableMediaCache
    private lazy var mediaRenderer = FullscreenTokenMediaRenderer(
        containerView: view,
        artworkDependencyCache: artworkDependencyCache
    )
    private var placeholderStack: UIStackView!
    private var renderedTokenKey = ""
    private var willOrDidAppear = false
    private var laidOutArtworkSize: CGSize = .zero
    private var artworkResizeTask: Task<Void, Never>?
    private var htmlDocumentTask: Task<Void, Never>?
    
    init(
        artworkDependencyCache: PersistentArtworkDependencyCache = .shared,
        mediaCache: DownloadableMediaCache = .shared
    ) {
        self.artworkDependencyCache = artworkDependencyCache
        self.mediaCache = mediaCache
        super.init(nibName: nil, bundle: nil)
        currentDisplay = self
        renderCurrentItem()
    }
    
    required init?(coder: NSCoder) {
        fatalError("yo")
    }

    isolated deinit {
        artworkResizeTask?.cancel()
        htmlDocumentTask?.cancel()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .darkGray
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        willOrDidAppear = true
        renderCurrentItem()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        willOrDidAppear = false
        artworkResizeTask?.cancel()
        if htmlDocumentTask != nil {
            htmlDocumentTask?.cancel()
            htmlDocumentTask = nil
            renderedTokenKey = ""
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let size = view.bounds.size
        guard size.width > 0, size.height > 0, size != laidOutArtworkSize else { return }
        let hadLayout = laidOutArtworkSize != .zero
        laidOutArtworkSize = size
        artworkResizeTask?.cancel()
        artworkResizeTask = nil
        guard hadLayout, willOrDidAppear, view.window != nil else { return }
        let tokenKey = renderedTokenKey
        artworkResizeTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
            guard let self, self.renderedTokenKey == tokenKey, self.viewIfLoaded?.window != nil else { return }
            self.artworkResizeTask = nil
            _ = self.mediaRenderer.reloadStableArtworkAfterResize()
        }
    }
    
    private func ensurePlaceholder() {
        guard placeholderStack == nil else { return }
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 27
        imageView.image = Images.appIcon
        let label = UILabel()
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = Strings.selectSomethingInTheApp
        label.font = .preferredFont(forTextStyle: .largeTitle)
        label.textAlignment = .center
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        
        placeholderStack = UIStackView(arrangedSubviews: [imageView, label])
        placeholderStack.translatesAutoresizingMaskIntoConstraints = false
        placeholderStack.axis = .vertical
        placeholderStack.spacing = 34
        placeholderStack.alignment = .center
        placeholderStack.overrideUserInterfaceStyle = .dark
        view.addSubview(placeholderStack)
        
        NSLayoutConstraint.activate([
            placeholderStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            placeholderStack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 192),
            imageView.heightAnchor.constraint(equalTo: imageView.widthAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20)
        ])
    }
    
    fileprivate func renderCurrentItem() {
        guard willOrDidAppear else { return }
        
        ensurePlaceholder()
        
        let tokenKey = renderKey(for: currentToken)
        guard tokenKey != renderedTokenKey else { return }

        artworkResizeTask?.cancel()
        artworkResizeTask = nil
        htmlDocumentTask?.cancel()
        htmlDocumentTask = nil
        renderedTokenKey = tokenKey
        if let nativeRenderKind = currentToken.nativeMetalCardRenderKind {
            renderNativeMetalCard(currentToken, renderKind: nativeRenderKind)
        } else if case .staticImage = currentToken.media {
            renderImage(currentToken, tokenKey: tokenKey)
        } else if case .html = currentToken.media {
            renderHTMLDocument(currentToken, tokenKey: tokenKey)
        } else {
            renderWebContent(currentToken.html)
        }
    }

    private func renderHTMLDocument(_ token: GeneratedToken, tokenKey: String) {
        renderWebContent(token.html)
        guard let descriptor = CollectionCatalog.downloadableMediaDescriptor(
            for: CollectionCatalog.tokenContext(for: token)
        ) else { return }

        let mediaCache = mediaCache
        htmlDocumentTask = Task { @MainActor [weak self] in
            guard !Task.isCancelled else { return }
            let lease = mediaCache.fileLease(for: descriptor)
            defer {
                lease.release()
                if !Task.isCancelled, self?.renderedTokenKey == tokenKey {
                    self?.htmlDocumentTask = nil
                }
            }
            guard let fileURL = await mediaCache.file(for: descriptor), !Task.isCancelled else { return }
            let sourceURL = await mediaCache.downloadedSourceURL(for: descriptor)
            guard !Task.isCancelled,
                  let document = await DownloadableTokenHTML.renderDocument(
                    at: fileURL, baseURL: sourceURL.absoluteString
                  ),
                  !Task.isCancelled,
                  let self, self.renderedTokenKey == tokenKey else { return }
            self.renderWebContent(document.html)
        }
    }

    private func renderImage(_ token: GeneratedToken, tokenKey: String) {
        mediaRenderer.renderImage(
            key: tokenKey,
            hideImageUntilLoaded: true,
            onBegin: { [weak self] in
                self?.placeholderStack.isHidden = false
            },
            load: { completion in
                let task = Task { @MainActor in
                    let image = await DownloadableMediaCache.shared.image(
                        for: token
                    )
                    guard !Task.isCancelled else { return }
                    completion(image)
                }
                return { task.cancel() }
            },
            fallbackToWebContent: { [weak self] in
                self?.renderWebContent(token.html)
            },
            onSuccess: { [weak self] in
                self?.placeholderStack.isHidden = true
            }
        )
    }

    private func renderWebContent(_ html: String) {
        ensurePlaceholder()
        mediaRenderer.configureArtBlocksRendering(
            collectionId: currentToken.fullCollectionId,
            tokenId: currentToken.id
        )
        mediaRenderer.renderWebContent(
            html,
            hidesEmptyWebContent: true,
            onBegin: { [weak self] in
                self?.placeholderStack.isHidden = !html.isEmpty
            }
        )
    }

    private func renderNativeMetalCard(_ token: GeneratedToken, renderKind: NativeMetalCardRenderKind) {
        ensurePlaceholder()
        placeholderStack.isHidden = true
        mediaRenderer.renderNativeMetalCard(tokenId: token.id, renderKind: renderKind)
    }

    private func renderKey(for token: GeneratedToken) -> String {
        "\(token.fullCollectionId)|\(token.id)"
    }
    
}
