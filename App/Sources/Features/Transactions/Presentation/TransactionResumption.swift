import SwiftUI

/// Resumes the watches of pending transactions when the scene becomes active or the provider connection changes.
private struct TransactionResumption: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(TransactionStore.self) private var transactions
    @Environment(ProviderStore.self) private var providers
    /// The provider connection at the last resumption, or `nil` before the first.
    @State private var resumedConnection: ProviderClient.Endpoint?

    func body(content: Content) -> some View {
        let trigger = Trigger(isActive: scenePhase == .active && providers.isRead,
                              providerConnection: providers.connection)
        content
            .task(id: trigger) {
                guard trigger.isActive else { return }
                let isNewConnection = resumedConnection != nil && trigger.providerConnection != resumedConnection
                resumedConnection = trigger.providerConnection
                await transactions.resume(replacingFailedWatches: isNewConnection)
            }
    }

    /// The state whose changes resume the watches.
    private struct Trigger: Equatable {
        let isActive: Bool
        let providerConnection: ProviderClient.Endpoint?
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
