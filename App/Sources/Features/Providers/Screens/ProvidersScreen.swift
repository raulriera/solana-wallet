import SwiftUI

/// Lists the RPC providers with a checkmark on the one that every window uses.
struct ProvidersScreen: View {
    @Environment(\.palette) private var palette
    @Bindable var coordinator: ProvidersCoordinator

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

            ProviderSelectionSection(selection: coordinator.selection, customRPCs: coordinator.customRPCs,
                                     removal: $coordinator.removal, actions: coordinator)
        }
        // Each save adds or deletes one custom RPC, so its rows animate whenever the count changes.
        .animation(.default, value: coordinator.customRPCs.count)
        .navigationTitle("Providers")
        .navigationBarTitleDisplayMode(.inline)
        .foregroundStyle(palette.primaryText, palette.secondaryText)
        .scrollContentBackground(.hidden)
        .readableContentWidth()
        .background(palette.background)
    }
}
