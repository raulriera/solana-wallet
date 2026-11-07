import SwiftUI

/// Resumes the watches of pending transactions when the scene becomes active or the provider connection changes.
private struct TransactionResumption: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(TransactionStore.self) private var transactions
    @Environment(RPCStore.self) private var rpcStore
    /// The provider connection at the last resumption, or `nil` before the first.
    @State private var resumedConnection: SelectedRPCProvider.Endpoint?

    func body(content: Content) -> some View {
        let trigger = Trigger(isActive: scenePhase == .active && rpcStore.isRead,
                              rpcConnection: rpcStore.connection)
        content
            .task(id: trigger) {
                guard trigger.isActive else { return }
                let isNewConnection = resumedConnection != nil && trigger.rpcConnection != resumedConnection
                resumedConnection = trigger.rpcConnection
                await transactions.resume(replacingFailedWatches: isNewConnection)
            }
    }

    /// The state whose changes resume the watches.
    private struct Trigger: Equatable {
        let isActive: Bool
        let rpcConnection: SelectedRPCProvider.Endpoint?
    }
}

extension View {
    /// Resumes the watches of pending transactions when the scene becomes active or the provider connection changes.
    ///
    /// - Returns: A view that resumes the watches.
    func transactionResumption() -> some View {
        modifier(TransactionResumption())
    }
}
