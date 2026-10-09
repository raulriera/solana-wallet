import SwiftUI

/// Presents provider setup in its own navigation container, outside onboarding's flow.
struct ProviderSetupSheet: View {
    @Environment(\.dismiss) private var dismiss
    let submission: ProviderSubmission

    var body: some View {
        NavigationStack {
            ProviderSetupScreen(isKeyRejected: submission.isKeyRejected, submit: submission.submit)
                .providerSetupLifecycle(submission)
                .onChange(of: submission.isSaved) { dismiss() }
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
