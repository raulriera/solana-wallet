import SwiftUI

/// Reads the private balance of a window's account while the window is active, then polls it.
///
/// The balance is read again when the window becomes active, the account or network changes, or portfolios read
/// through another provider. Private notes have no account of the person's own to watch, so while the window stays
/// active the balance is polled; the model skips polls while private balances are off or polling is paused.
private struct PrivateBalanceObservation: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    let account: Account
    let model: PrivateBalanceModel
    let providerRevisions: ProviderRevisions
    let pollInterval: Duration

    func body(content: Content) -> some View {
        let session = Session(accountID: account.id, model: ObjectIdentifier(model), isActive: scenePhase == .active,
                              providerConnection: providerRevisions.connection.value)
        content
            .task(id: session) {
                guard session.isActive else { return }
                await model.refresh(for: account)
                // Each wait ends early, and polling stops, once the window leaves or the session changes.
                while (try? await Task.sleep(for: pollInterval)) != nil {
                    await model.poll()
                }
            }
    }

    /// What starts a new read of the balance.
    private struct Session: Equatable {
        let accountID: UUID
        let model: ObjectIdentifier
        let isActive: Bool
        let providerConnection: Int
    }
}

extension View {
    /// Reads the private balance of the window's account while the window is active, then polls it.
    /// - Parameters:
    ///   - account: The window's account.
    ///   - model: The window's private balance.
    ///   - providerRevisions: The app-wide provider changes, which read the balance again.
    ///   - pollInterval: The time between polls.
    /// - Returns: The window's content, reading its private balance.
    func privateBalanceObservation(of account: Account, model: PrivateBalanceModel,
                                   providerRevisions: ProviderRevisions,
                                   pollInterval: Duration = .seconds(30)) -> some View {
        modifier(PrivateBalanceObservation(account: account, model: model, providerRevisions: providerRevisions,
                                           pollInterval: pollInterval))
    }
}
