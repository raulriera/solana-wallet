import SwiftUI

/// Lists the RPC providers with a checkmark on the one that every window uses.
struct ProvidersScreen<Actions: View>: View {
    @Environment(\.palette) private var palette
    @Bindable var coordinator: ProvidersCoordinator
    private let actions: Actions

    /// Creates the provider list with sections of actions after it.
    /// - Parameters:
    ///   - coordinator: The provider choice that every window shares.
    ///   - actions: Sections that follow the list, such as onboarding's Continue.
    init(coordinator: ProvidersCoordinator, @ViewBuilder actions: () -> Actions) {
        self.coordinator = coordinator
        self.actions = actions()
    }

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

            actions
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

extension ProvidersScreen where Actions == EmptyView {
    /// Creates the provider list on its own, as Settings shows it.
    /// - Parameter coordinator: The provider choice that every window shares.
    init(coordinator: ProvidersCoordinator) {
        self.init(coordinator: coordinator) { EmptyView() }
    }
}
