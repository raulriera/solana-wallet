import SwiftUI

/// Collects an entry for an RPC provider, such as Helius's API key or a custom RPC URL.
struct RPCSetupScreen<EntryError: ProviderEntryError>: ProviderSetupScreen {
    let purpose: RPCEntryPurpose
    let submission: ProviderSetupModel<EntryError>

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
