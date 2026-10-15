import SwiftUI

/// Presents key entry in its own navigation container, over the screen that needs the key.
struct ProviderSetupSheet: View {
    let submission: ProviderSetupModel<ProviderConnectionError>

    var body: some View {
        NavigationStack {
            ProviderSetupScreen(purpose: .connect, submission: submission)
                .providerSetupLifecycle()
                .cancellationAction()
        }
    }
}
