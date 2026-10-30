import SwiftUI

/// Presents key entry in its own navigation stack.
struct ProviderSetupSheet: View {
    let submission: ProviderSetupModel<ProviderConnectionError>

    var body: some View {
        NavigationStack {
            ProviderSetupScreen(purpose: .connect, submission: submission)
                .providerSetupLifecycle()
                .cancellationAction()
        }
        .limitedTextSize()
    }
}
