import RPC
import SwiftUI

/// Reads and polls the private balance of a window's account while the window is active.
private struct PrivateBalanceObservation: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(PrivateBalanceStore.self) private var privateBalances
    @Environment(RPCStore.self) private var rpcStore
    let account: Account
    let network: Network

    func body(content: Content) -> some View {
        let session = Session(accountID: account.id, network: network,
                              isActive: scenePhase == .active && rpcStore.isRead)
        content
            .task(id: session) {
                guard session.isActive else { return }
                await privateBalances.observe(account, on: network)
            }
    }

    /// The identity of the observation.
    private struct Session: Equatable {
        let accountID: UUID
        let network: Network
        let isActive: Bool
    }
}

extension View {
    /// Reads and polls the private balance of the window's account while the window is active.
    ///
    /// - Parameters:
    ///   - account: The window's account.
    ///   - network: The window's network.
    /// - Returns: The view that observes the private balance.
    func privateBalanceObservation(of account: Account, on network: Network) -> some View {
        modifier(PrivateBalanceObservation(account: account, network: network))
    }
}
