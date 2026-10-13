import SwiftUI

/// Presents adding a token in its own navigation container, so the system places the sheet on each display.
///
/// The sheet closes itself on Cancel and once the token is added.
struct TokenAdditionSheet: View {
    @Environment(\.dismiss) private var dismiss
    let addition: TokenAdditionModel

    var body: some View {
        NavigationStack {
            TokenAdditionScreen(addition: addition)
                .tokenAdditionLifecycle()
                .onChange(of: addition.isAdded) { dismiss() }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        // Toolbar buttons keep the system's monochrome look; the theme's tint is for content.
                        Button("Cancel", role: .cancel) { dismiss() }
                            .tint(.primary)
                    }
                }
        }
    }
}
