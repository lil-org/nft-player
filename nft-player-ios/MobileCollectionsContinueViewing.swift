import SwiftUI
import UIKit

enum MobileCollectionsContinueViewingMetrics {
    static let maximumVisibleCount = 10
    static let horizontalContentInset: CGFloat = 16
}

private let continueViewingContentSizedCollectionNameMaxWidth: CGFloat = 250
private let continueViewingCoverThumbnailSize: CGFloat = 14
private let continueViewingCoverThumbnailCornerRadius: CGFloat = 3
private let continueViewingPillSpacing: CGFloat = 8

struct ContinueViewingPillsScrollView: View {
    let progresses: [MobileViewingProgress]
    let availableWidth: CGFloat
    let horizontalContentInset: CGFloat
    let resetID: Int
    let coverAssetName: (String) -> String
    let onSelect: (MobileViewingProgress) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: continueViewingPillSpacing) {
                ForEach(progresses, id: \.collectionId) { progress in
                    ContinueViewingButton(
                        progress: progress,
                        coverAssetName: coverAssetName(progress.collectionId)
                    ) {
                        onSelect(progress)
                    }
                }
            }
            .padding(.horizontal, horizontalContentInset)
            .frame(
                minWidth: availableWidth,
                alignment: progresses.count == 1 ? .center : .leading
            )
        }
        .frame(width: availableWidth)
        .id(resetID)
    }
}

private struct ContinueViewingButton: View {
    let progress: MobileViewingProgress
    let coverAssetName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                CollectionCoverThumbnail(assetName: coverAssetName)

                VStack(alignment: .leading, spacing: 2) {
                    Text(Strings.continueViewing)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    collectionName
                }

                Text(Strings.percent(progress.percent))
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background {
                CapsuleButtonBackground(isInteractive: true)
            }
            .clipShape(Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: "\(Strings.continueViewing), \(progress.collectionName)"))
    }

    private var collectionName: some View {
        Text(progress.collectionName)
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: continueViewingContentSizedCollectionNameMaxWidth, alignment: .leading)
            .layoutPriority(1)
    }
}

struct CollectionCoverThumbnail: View {
    let assetName: String
    var size: CGFloat = continueViewingCoverThumbnailSize
    var cornerRadius: CGFloat = continueViewingCoverThumbnailCornerRadius

    @Environment(\.displayScale) private var displayScale
    @State private var loadedImage: LoadedImage?
    @State private var pendingThumbnailLoadKey: String?

    var body: some View {
        ZStack {
            if let image = displayedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.white.opacity(0.18)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(.white.opacity(0.22), lineWidth: 0.5)
        }
        .accessibilityHidden(true)
        .task(id: thumbnailLoadKey) {
            await loadImage(for: thumbnailLoadKey)
        }
    }

    private var thumbnailLoadKey: String {
        "\(assetName)-\(displayScale)"
    }

    private var displayedImage: UIImage? {
        if let loadedImage, loadedImage.loadKey == thumbnailLoadKey {
            return loadedImage.image
        }
        let scale = displayScale > 0 ? displayScale : UIScreen.main.scale
        return MobileCollectionCoverImageCache.shared.cachedImage(
            assetName: assetName,
            targetSize: targetSize,
            displayScale: scale
        )
    }

    private var targetSize: CGSize {
        CGSize(width: size, height: size)
    }

    @MainActor
    private func loadImage(for loadKey: String) async {
        let scale = displayScale > 0 ? displayScale : UIScreen.main.scale
        pendingThumbnailLoadKey = loadKey
        if let cachedImage = MobileCollectionCoverImageCache.shared.cachedImage(
            assetName: assetName,
            targetSize: targetSize,
            displayScale: scale
        ) {
            loadedImage = LoadedImage(loadKey: loadKey, image: cachedImage)
            return
        }

        loadedImage = nil
        let requestedAssetName = assetName
        MobileCollectionCoverImageCache.shared.loadImage(
            assetName: requestedAssetName,
            targetSize: targetSize,
            displayScale: scale
        ) { loadedImage in
            guard pendingThumbnailLoadKey == loadKey,
                  let loadedImage else {
                return
            }
            self.loadedImage = LoadedImage(loadKey: loadKey, image: loadedImage)
        }
    }

    private struct LoadedImage {
        let loadKey: String
        let image: UIImage
    }
}

