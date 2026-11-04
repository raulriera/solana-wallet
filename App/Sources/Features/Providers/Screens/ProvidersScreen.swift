import SwiftUI

/// Lists the RPC providers with a checkmark on the one in use.
struct ProvidersScreen<Actions: View>: View {
    @Environment(ProviderStore.self) private var providers
    @Bindable var coordinator: ProvidersCoordinator
    private let actions: Actions

    /// Creates the provider list with sections of actions after it.
    ///
    /// - Parameters:
    ///   - coordinator: The coordinator of provider changes and pushed screens.
    ///   - actions: The sections that follow the list.
    init(coordinator: ProvidersCoordinator, @ViewBuilder actions: () -> Actions) {
        self.coordinator = coordinator
        self.actions = actions()
    }

    var body: some View {
        let settings = providers.settings
        let customRPCs = settings?.customRPCs ?? []
        Form {
            Section {
                TitleCardContent(
                    title: "Providers",
                    message: "Your wallets connect directly to Solana through the RPC provider you choose.",
                    systemImage: "point.3.filled.connected.trianglepath.dotted"
                )
            }

            ProviderSelectionSection(selection: settings?.selection,
                                     customRPCs: customRPCs,
                                     removal: $coordinator.removal,
                                     actions: coordinator)

            actions
        }
        .animation(.default, value: customRPCs.count)
        .navigationTitle("Providers")
        .navigationBarTitleDisplayMode(.inline)
    }
}

extension ProvidersScreen where Actions == EmptyView {
    /// Creates the provider list without actions.
    ///
    /// - Parameter coordinator: The coordinator of provider changes and pushed screens.
    init(coordinator: ProvidersCoordinator) {
        self.init(coordinator: coordinator) { EmptyView() }
    }
}
