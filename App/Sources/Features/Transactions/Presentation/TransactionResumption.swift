import SwiftUI

/// Watches the shared transactions' pending records again each time the window's scene becomes active, so a record
/// whose watch a relaunch stopped still settles, and replaces watches that stopped with an error after each new provider
/// connection, which may fix the error.
private struct TransactionResumption: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(TransactionStore.self) private var transactions
    /// The provider connection of the last resumption, or `nil` before the first.
    @State private var resumedConnection: Int?
    let providerRevisions: ProviderRevisions

    /// Resumes the watches for the lifetime of the content's task.
    /// - Parameter content: The window's content.
    /// - Returns: Content whose task resumes the watches when its scene becomes active or the connection changes.
    func body(content: Content) -> some View {
        let trigger = Trigger(isActive: scenePhase == .active, providerConnection: providerRevisions.connection.value)
        content
            .task(id: trigger) {
                guard trigger.isActive else { return }
                // Errors such as a rate limit aren't retried on their own; a new connection may fix them.
                let isNewConnection = resumedConnection.map { $0 != trigger.providerConnection } ?? false
                resumedConnection = trigger.providerConnection
                await transactions.resume(replacingFailedWatches: isNewConnection)
            }
    }

    /// What resumes the watches: the scene becoming active, or a new provider connection from any window.
    private struct Trigger: Equatable {
        let isActive: Bool
        let providerConnection: Int
    }
}

extension View {
    /// Watches the shared transactions' pending records again each time this view's scene becomes active, including at
    /// launch, and replaces the watches that stopped with an error after each new provider connection.
    /// - Parameter providerRevisions: The shared counts of provider changes; each new connection retries failed
    ///   watches.
    /// - Returns: A view whose task resumes the watches.
    func transactionResumption(providerRevisions: ProviderRevisions) -> some View {
        modifier(TransactionResumption(providerRevisions: providerRevisions))
    }
}
