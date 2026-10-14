import SwiftUI
import Transactions

/// Observes the window's wallet while its scene is active, whichever section is visible.
private struct PortfolioObservation: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    let account: Account
    let coordinator: any PortfolioCoordinating
    let providerRevisions: ProviderRevisions

    /// Runs observation for the lifetime of the content's task.
    /// - Parameter content: The window's sections; a task inside one section would stop on every section switch.
    /// - Returns: Content that observes the wallet until the scene leaves or the wallet changes.
    func body(content: Content) -> some View {
        let session = Session(accountID: account.id, coordinator: ObjectIdentifier(coordinator),
                              isActive: scenePhase == .active,
                              providerConnection: providerRevisions.connection.value)
        content
            .task(id: session) { await coordinator.observe(for: account.address.value, isActive: session.isActive) }
    }

    /// The observation's identity: a new wallet, a replaced coordinator, scene activity, or a new provider connection
    /// from any window restarts it.
    ///
    /// The coordinator itself, not the window's stored network, keys the task, so observation always runs on the
    /// coordinator that the window shows.
    private struct Session: Equatable {
        let accountID: UUID
        let coordinator: ObjectIdentifier
        let isActive: Bool
        let providerConnection: Int
    }
}

extension View {
    /// Observes a wallet's portfolio for as long as this view's scene is active.
    /// - Parameters:
    ///   - account: The window's wallet.
    ///   - coordinator: The window's portfolio presentation; a replacement, as for another network, restarts
    ///     observation.
    ///   - providerRevisions: The shared counts of provider changes; each new connection restarts observation.
    /// - Returns: A view whose task observes the wallet, independent of the visible section.
    func portfolioObservation(of account: Account, coordinator: any PortfolioCoordinating,
                              providerRevisions: ProviderRevisions) -> some View {
        modifier(PortfolioObservation(account: account, coordinator: coordinator, providerRevisions: providerRevisions))
    }
}
