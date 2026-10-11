import SwiftUI

/// Lists the RPC providers with a checkmark on the one that every window uses.
struct ProvidersScreen: View {
    @Environment(\.palette) private var palette
    let flow: ProvidersFlow

    var body: some View {
        Form {
            Section {
                TitleCardContent(
                    title: "Providers",
                    message: "Your wallets connect directly to Solana through the RPC provider you choose.",
                    systemImage: "point.3.filled.connected.trianglepath.dotted"
                )
            }
            .listRowBackground(palette.surface)

            ProviderSelectionSection(selection: flow.selection, actions: flow)
        }
        .navigationTitle("Providers")
        .navigationBarTitleDisplayMode(.inline)
        .foregroundStyle(palette.primaryText, palette.secondaryText)
        .scrollContentBackground(.hidden)
        .background(palette.background)
    }
}
