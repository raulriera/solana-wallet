import SwiftUI

/// Watches the shared transactions' pending records again each time the window's scene becomes active, so a record
/// whose watch a relaunch stopped still settles, and replaces watches that stopped with an error after each new provider
/// connection, which may fix the error.
private struct TransactionResumption: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(TransactionStore.self) private var transactions
    @Environment(ProviderStore.self) private var providers
    /// The provider connection of the last resumption, or `nil` before the first or while the settings aren't read.
    @State private var resumedConnection: ProviderClient.Endpoint?

    /// Resumes the watches for the lifetime of the content's task.
    /// - Parameter content: The window's content.
    /// - Returns: Content whose task resumes the watches when its scene becomes active or the connection changes.
    func body(content: Content) -> some View {
        // Watches run only while the provider settings are read, so a reset that erases them resumes nothing.
        let trigger = Trigger(isActive: scenePhase == .active && providers.isRead,
                              providerConnection: providers.connection)
        content
            .task(id: trigger) {
                guard trigger.isActive else { return }
                // Errors such as a rate limit aren't retried on their own; a new connection may fix them.
                let isNewConnection = ProviderClient.Endpoint.isNew(trigger.providerConnection,
                                                                    after: resumedConnection)
                resumedConnection = trigger.providerConnection
                await transactions.resume(replacingFailedWatches: isNewConnection)
            }
    }

    /// What resumes the watches: the scene becoming active, or a new provider connection from any window.
    private struct Trigger: Equatable {
        let isActive: Bool
        let providerConnection: ProviderClient.Endpoint?
    }
}

extension View {
    /// Watches the shared transactions' pending records again each time this view's scene becomes active, including at
    /// launch, and replaces the watches that stopped with an error after each new provider connection.
    /// - Returns: A view whose task resumes the watches.
    func transactionResumption() -> some View {
        modifier(TransactionResumption())
    }
}
