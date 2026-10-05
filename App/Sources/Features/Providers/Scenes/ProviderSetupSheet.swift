import SwiftUI

/// Presents provider setup in its own navigation container, outside onboarding's flow.
struct ProviderSetupSheet: View {
    @Environment(\.dismiss) private var dismiss
    let submission: ProviderSubmission

    var body: some View {
        NavigationStack {
            ProviderSetupScreen(isKeyRejected: submission.isKeyRejected, submit: submission.submit)
                .providerSetupLifecycle(submission)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", role: .cancel) { dismiss() }
                    }
                }
        }
    }
}
