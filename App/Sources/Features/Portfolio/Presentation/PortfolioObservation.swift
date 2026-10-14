import SwiftUI
import Transactions

/// Observes the window's wallet while its scene is active, whichever section is visible.
private struct PortfolioObservation: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    let account: Account
    let coordinator: any PortfolioCoordinating
    let providerRevision: Revision

    /// Runs observation for the lifetime of the content's task.
    /// - Parameter content: The window's sections; a task inside one section would stop on every section switch.
    /// - Returns: Content that observes the wallet until the scene leaves or the wallet changes.
    func body(content: Content) -> some View {
        let session = Session(accountID: account.id, coordinator: ObjectIdentifier(coordinator),
                              isActive: scenePhase == .active, providerRevision: providerRevision.value)
        content
            .task(id: session) { await coordinator.observe(for: account.address.value, isActive: session.isActive) }
    }

    /// The observation's identity: a new wallet, a replaced coordinator, scene activity, or a provider change in any
    /// window restarts it.
    ///
    /// The coordinator itself, not the window's stored network, keys the task, so observation always runs on the
    /// coordinator that the window shows.
    private struct Session: Equatable {
        let accountID: UUID
        let coordinator: ObjectIdentifier
        let isActive: Bool
        let providerRevision: Int
    }
}

extension View {
    /// Observes a wallet's portfolio for as long as this view's scene is active.
    /// - Parameters:
    ///   - account: The window's wallet.
    ///   - coordinator: The window's portfolio presentation; a replacement, as for another network, restarts
    ///     observation.
    ///   - providerRevision: The shared count of provider changes; each one restarts observation.
    /// - Returns: A view whose task observes the wallet, independent of the visible section.
    func portfolioObservation(of account: Account, coordinator: any PortfolioCoordinating,
                              providerRevision: Revision) -> some View {
        modifier(PortfolioObservation(account: account, coordinator: coordinator, providerRevision: providerRevision))
    }
}
