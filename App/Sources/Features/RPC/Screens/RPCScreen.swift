import SwiftUI

/// Lists the RPC providers with a checkmark on the one in use.
struct RPCScreen<Actions: View>: View {
    @Environment(RPCStore.self) private var rpcStore
    let coordinator: RPCCoordinator
    private let actions: Actions

    /// Creates the provider list with sections of actions after it.
    ///
    /// - Parameters:
    ///   - coordinator: The coordinator of provider changes and pushed screens.
    ///   - actions: The sections that follow the list.
    init(coordinator: RPCCoordinator, @ViewBuilder actions: () -> Actions) {
        self.coordinator = coordinator
        self.actions = actions()
    }

    var body: some View {
        let settings = rpcStore.settings
        let customRPCs = settings?.customRPCs ?? []
        Form {
            Section {
                TitleCardContent(
                    title: "RPC",
                    message: "Your wallets connect directly to Solana through the RPC provider you choose.",
                    systemImage: "point.3.filled.connected.trianglepath.dotted"
                )
            }

            RPCSelectionSection(selection: settings?.selection,
                                customRPCs: customRPCs,
                                actions: coordinator)

            actions
        }
        .formStyle(.choices(checkmark: .leading))
        .animation(.default, value: customRPCs.count)
        .navigationTitle("RPC")
        .navigationBarTitleDisplayMode(.inline)
    }
}

extension RPCScreen where Actions == EmptyView {
    /// Creates the provider list without actions.
    ///
    /// - Parameter coordinator: The coordinator of provider changes and pushed screens.
    init(coordinator: RPCCoordinator) {
        self.init(coordinator: coordinator) { EmptyView() }
    }
}
