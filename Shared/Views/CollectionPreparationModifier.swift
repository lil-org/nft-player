import SwiftUI

extension View {
    func collectionPreparation(
        _ state: CollectionPreparationState,
        onCancel: @escaping () -> Void
    ) -> some View {
        modifier(CollectionPreparationModifier(state: state, onCancel: onCancel))
    }
}

private struct CollectionPreparationModifier: ViewModifier {
    @Bindable var state: CollectionPreparationState
    let onCancel: () -> Void

    func body(content: Content) -> some View {
        content
            .overlay {
                if state.isLoading {
                    VStack(spacing: 16) {
                        ProgressView(Strings.loadingCollection)
                        Button(Strings.cancel, action: onCancel)
                    }
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
            .alert(
                Strings.collectionLoadFailed,
                isPresented: Binding(
                    get: { state.errorMessage != nil },
                    set: { if !$0 { state.errorMessage = nil } }
                )
            ) {
                Button(Strings.retry, action: state.retry)
                Button(Strings.cancel, role: .cancel, action: onCancel)
            } message: {
                Text(state.errorMessage ?? "")
            }
    }
}
