import RPC
import SwiftUI

/// Reads the private balance of a window's account while the window is active, then polls it.
///
/// The balance is read again when the window becomes active or the account or network changes. Windows that show the
/// same account on the same network share one read and one poll loop, which reads again after each of the account's
/// private moves settles and after a new provider connection.
private struct PrivateBalanceObservation: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(PrivateBalanceStore.self) private var privateBalances
    @Environment(ProviderStore.self) private var providers
    let account: Account
    let network: Network

    func body(content: Content) -> some View {
        let session = Session(accountID: account.id, network: network,
                              isActive: scenePhase == .active && providers.isRead)
        content
            .task(id: session) {
                guard session.isActive else { return }
                await privateBalances.observe(account, on: network)
            }
    }

    /// The observation's identity: another account, another network, or scene activity restarts it. It runs only
    /// while the provider settings are read, so a reset stops it.
    ///
    /// Settled moves and new providers don't restart it: the shared balance reads again after them itself.
    private struct Session: Equatable {
        let accountID: UUID
        let network: Network
        let isActive: Bool
    }
}

extension View {
    /// Reads the private balance of the window's account while the window is active, then polls it.
    ///
    /// The balance is the environment's ``PrivateBalanceStore``, which SOL's details and the token list read.
    /// - Parameters:
    ///   - account: The window's account.
    ///   - network: The window's network.
    /// - Returns: The window's content, reading its private balance.
    func privateBalanceObservation(of account: Account, on network: Network) -> some View {
        modifier(PrivateBalanceObservation(account: account, network: network))
    }
}
