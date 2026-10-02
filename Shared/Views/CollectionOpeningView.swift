import SwiftUI

struct CollectionOpeningView: View {
    let destination: CollectionOpeningDestination
    let preparation: CollectionPreparationState
    var topContentInset: CGFloat = 0
    var bottomContentInset: CGFloat = 0

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        ZStack {
            if let errorMessage = preparation.errorMessage {
                VStack(spacing: 16) {
                    Text(Strings.collectionLoadFailed)
                        .font(.headline)
                    Text(errorMessage)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button(Strings.retry, action: preparation.retry)
                        .accessibilityIdentifier("CollectionOpeningRetry")
                }
                .padding(24)
                .frame(maxWidth: 480)
                .accessibilityIdentifier("CollectionOpeningError")
            } else {
                Canvas { context, size in
                    for frame in destination.placeholderFrames(
                        viewportSize: size,
                        displayScale: displayScale,
                        topContentInset: topContentInset,
                        bottomContentInset: bottomContentInset
                    ) {
                        context.fill(Path(frame), with: .color(placeholderColor))
                    }
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .accessibilityIdentifier("CollectionOpeningDestination")
    }

    private var placeholderColor: Color {
#if os(macOS)
        Color(white: 0.09)
#else
        Color(white: 0.65).opacity(0.18)
#endif
    }
}
