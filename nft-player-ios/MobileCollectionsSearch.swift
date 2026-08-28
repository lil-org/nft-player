import SwiftUI
import UIKit

enum MobileCollectionsSearchMetrics {
    static let coverThumbnailSize: CGFloat = 44
}

private let searchResultCoverThumbnailCornerRadius: CGFloat = 10

private enum MobileCollectionSearchIndex {
    private struct Entry {
        let item: MobileCollectionItem
        let haystack: String
    }

    private static let entries: [Entry] = MobileCollectionCatalog.allItems.map { item in
        let artists = SuggestedItemsService.artists(forCollectionId: item.id)
        let components = [item.name]
            + artists.map(\.name)
            + artists.flatMap { $0.links.map(\.title) }
        return Entry(item: item, haystack: components.joined(separator: " "))
    }

    static func matches(query: String) -> [MobileCollectionItem] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return entries.map(\.item) }
        return entries
            .filter { $0.haystack.localizedStandardContains(trimmedQuery) }
            .map(\.item)
    }
}

struct MobileCollectionsSearchBar: View {
    @Binding var query: String
    let isFocusSuspended: Bool

    var body: some View {
        HStack(spacing: 6) {
            Images.search
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white.opacity(0.55))
            MobileSearchTextField(text: $query, placeholder: Strings.search, isFocusSuspended: isFocusSuspended)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Images.clearText
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.55))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background {
            CapsuleButtonBackground()
        }
        .clipShape(Capsule())
        .frame(maxWidth: .infinity)
    }
}

private struct MobileSearchTextField: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let isFocusSuspended: Bool

    func makeUIView(context: Context) -> AutoFocusTextField {
        let textField = AutoFocusTextField()
        textField.delegate = context.coordinator
        textField.font = .preferredFont(forTextStyle: .subheadline)
        textField.textColor = .white
        textField.tintColor = .white
        textField.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: UIColor.white.withAlphaComponent(0.45)]
        )
        textField.autocapitalizationType = .none
        textField.autocorrectionType = .no
        textField.spellCheckingType = .no
        textField.returnKeyType = .search
        textField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textField.addTarget(context.coordinator, action: #selector(Coordinator.textDidChange(_:)), for: .editingChanged)
        textField.isFocusSuspended = isFocusSuspended
        return textField
    }

    func updateUIView(_ textField: AutoFocusTextField, context: Context) {
        if textField.text != text {
            textField.text = text
        }
        textField.isFocusSuspended = isFocusSuspended
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        private let text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        @objc func textDidChange(_ textField: UITextField) {
            text.wrappedValue = textField.text ?? ""
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            return true
        }
    }

    final class AutoFocusTextField: UITextField {
        var isFocusSuspended = false {
            didSet {
                guard window != nil else { return }
                if isFocusSuspended {
                    resignFirstResponder()
                } else if oldValue {
                    scheduleAutoFocus()
                }
            }
        }

        override var intrinsicContentSize: CGSize {
            CGSize(width: UIView.layoutFittingExpandedSize.width, height: super.intrinsicContentSize.height)
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil, !isFocusSuspended else { return }
            scheduleAutoFocus()
        }

        private func scheduleAutoFocus() {
            Task { @MainActor [weak self] in
                await Task.yield()
                guard let self, self.window != nil, !self.isFocusSuspended else { return }
                self.becomeFirstResponder()
            }
        }
    }
}

struct MobileCollectionsSearchResultsView: View {
    let query: String
    let onSelect: (MobileCollectionItem) -> Void

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.regularMaterial)
                .ignoresSafeArea()
            let results = MobileCollectionSearchIndex.matches(query: query)
            if results.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(results) { item in
                            resultRow(for: item)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .scrollDismissesKeyboard(.immediately)
            }
        }
    }

    private func resultRow(for item: MobileCollectionItem) -> some View {
        Button {
            onSelect(item)
        } label: {
            HStack(spacing: 12) {
                CollectionCoverThumbnail(
                    assetName: item.coverAssetName,
                    size: MobileCollectionsSearchMetrics.coverThumbnailSize,
                    cornerRadius: searchResultCoverThumbnailCornerRadius
                )
                Text(item.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Text(Strings.nothingFound)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.8))
            Button {
                UIApplication.shared.open(URL.mail)
            } label: {
                Text(Strings.sendFeedback)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background {
                        CapsuleButtonBackground(isInteractive: true)
                    }
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
