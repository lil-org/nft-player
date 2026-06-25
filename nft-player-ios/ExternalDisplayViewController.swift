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
    
    private lazy var mediaRenderer = FullscreenTokenMediaRenderer(containerView: view)
    private var placeholderStack: UIStackView!
    private var renderedTokenKey = ""
    private var willOrDidAppear = false
    
    init() {
        super.init(nibName: nil, bundle: nil)
        currentDisplay = self
        renderCurrentItem()
    }
    
    required init?(coder: NSCoder) {
        fatalError("yo")
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

        renderedTokenKey = tokenKey
        if let nativeRenderKind = currentToken.nativeMetalCardRenderKind {
            renderNativeMetalCard(currentToken, renderKind: nativeRenderKind)
        } else if case .staticImage = currentToken.media {
            renderImage(currentToken, tokenKey: tokenKey)
        } else {
            renderWebContent(currentToken.html)
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
                DownloadableMediaCache.shared.loadImage(for: token, completion: completion)
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
