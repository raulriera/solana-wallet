import SwiftUI

/// Presents key entry in its own navigation container, over the screen that needs the key.
struct ProviderSetupSheet: View {
    @Environment(\.dismiss) private var dismiss
    let submission: ProviderSubmission<ProviderConnectionError>

    var body: some View {
        NavigationStack {
            ProviderSetupScreen(purpose: .connect, submission: submission)
                .providerSetupLifecycle(submission)
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
