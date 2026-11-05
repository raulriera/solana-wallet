import SwiftUI

/// Collects an entry for an RPC provider, such as Helius's API key or a custom RPC URL.
struct RPCSetupScreen<Submission: ProviderSubmitting>: View {
    let purpose: RPCEntryPurpose
    let submission: Submission

    var body: some View {
        ProviderEntryForm(title: purpose.title, label: purpose.label, kind: purpose.kind, header: purpose.header,
                          footer: purpose.footer, action: purpose.action, submission: submission) {
            if purpose == .connect {
                Section {
                    TitleCardContent(
                        title: "Connect to Helius",
                        message: "This wallet connects directly to Solana through Helius. Enter your Helius API key to load your balances.",
                        systemImage: "point.3.filled.connected.trianglepath.dotted"
                    )
                }
            }
        } help: {
            if purpose.kind == .key {
                // swift-format-ignore: NeverForceUnwrap
                Link("Get an API key from Helius", destination: URL(string: "https://dashboard.helius.dev")!)
            }
        }
    }
}

extension RPCSetupScreen {
    /// Runs the screen's accepted entry checks and closes it once the entry is saved.
    ///
    /// - Returns: The screen with managed entry checks.
    func providerSetupLifecycle<EntryError: ProviderEntryError>() -> some View
    where Submission == ProviderSetupModel<EntryError> {
        modifier(ProviderSetupLifecycle(submission: submission))
    }
}

#Preview("Empty") {
    NavigationStack {
        RPCSetupScreen(purpose: .connect, submission: PreviewSubmission<RPCConnectionError>(rejection: nil))
    }
    .tint(RenderedPalette(OriginalAppearance.palette).primary)
}

#Preview("Rejected key") {
    NavigationStack {
        RPCSetupScreen(purpose: .connect, submission: PreviewSubmission(rejection: RPCConnectionError.invalidKey))
    }
    .tint(RenderedPalette(OriginalAppearance.palette).primary)
}

#Preview("Add") {
    NavigationStack {
        RPCSetupScreen(purpose: .add, submission: PreviewSubmission<RPCConnectionError>(rejection: nil))
    }
    .tint(RenderedPalette(OriginalAppearance.palette).primary)
}

#Preview("Change") {
    NavigationStack {
        RPCSetupScreen(purpose: .change, submission: PreviewSubmission<RPCConnectionError>(rejection: nil))
    }
    .tint(RenderedPalette(OriginalAppearance.palette).primary)
}

#Preview("Add Custom RPC") {
    NavigationStack {
        RPCSetupScreen(purpose: .customRPC, submission: PreviewSubmission<CustomRPCError>(rejection: nil))
    }
    .tint(RenderedPalette(OriginalAppearance.palette).primary)
}

#Preview("No live updates") {
    NavigationStack {
        RPCSetupScreen(purpose: .customRPC, submission: PreviewSubmission(rejection: CustomRPCError.noLiveUpdates))
    }
    .tint(RenderedPalette(OriginalAppearance.palette).primary)
}
