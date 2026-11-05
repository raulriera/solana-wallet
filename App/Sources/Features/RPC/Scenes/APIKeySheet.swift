import SwiftUI

/// Presents key entry in its own navigation stack.
struct APIKeySheet: View {
    let submission: ProviderSetupModel<RPCConnectionError>

    var body: some View {
        NavigationStack {
            RPCSetupScreen(purpose: .connect, submission: submission)
                .providerSetupLifecycle()
                .cancellationAction()
        }
        .limitedTextSize()
    }
}
