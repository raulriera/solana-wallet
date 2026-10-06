import SwiftUI
import Transactions

/// Observes the window's wallet while its scene is active, whichever section is visible.
private struct PortfolioObservation: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    let account: Account
    let coordinator: any PortfolioCoordinating
    let keyRevision: ProviderKeyRevision

    /// Runs observation for the lifetime of the content's task.
    /// - Parameter content: The window's sections; a task inside one section would stop on every section switch.
    /// - Returns: Content that observes the wallet until the scene leaves or the wallet changes.
    func body(content: Content) -> some View {
        let session = Session(accountID: account.id, isActive: scenePhase == .active, keyRevision: keyRevision.value)
        content
            .task(id: session) { await coordinator.observe(for: account.address.value, isActive: session.isActive) }
    }

    /// The observation's identity: a new wallet, scene activity, or a key saved in any window restarts it.
    private struct Session: Equatable {
        let accountID: UUID
        let isActive: Bool
        let keyRevision: Int
    }
}

extension View {
    /// Observes a wallet's portfolio for as long as this view's scene is active.
    /// - Parameters:
    ///   - account: The window's wallet.
    ///   - coordinator: The window's portfolio presentation.
    ///   - keyRevision: The shared count of saved provider keys; a new key restarts observation.
    /// - Returns: A view whose task observes the wallet, independent of the visible section.
    func portfolioObservation(of account: Account, coordinator: any PortfolioCoordinating,
                              keyRevision: ProviderKeyRevision) -> some View {
        modifier(PortfolioObservation(account: account, coordinator: coordinator, keyRevision: keyRevision))
    }
}
