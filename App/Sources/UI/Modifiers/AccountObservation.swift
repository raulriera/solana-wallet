import RPC
import SwiftUI

/// Observes an account through a store while the scene is in the foreground and the provider settings are read.
private struct AccountObservation<Store: AccountObserving>: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(Store.self) private var store
    @Environment(RPCStore.self) private var rpcStore
    let account: Account
    let network: Network

    func body(content: Content) -> some View {
        let session = Session(accountID: account.id, network: network,
                              isActive: scenePhase != .background && rpcStore.isRead)
        content
            .task(id: session) {
                guard session.isActive else { return }
                await store.observe(account, on: network)
            }
    }

    /// The identity of a running observation.
    private struct Session: Equatable {
        let accountID: UUID
        let network: Network
        let isActive: Bool
    }
}

extension View {
    /// Observes an account through a store in the environment while the scene is in the foreground and the provider
    /// settings are read.
    ///
    /// - Parameters:
    ///   - account: The account to observe.
    ///   - network: The network to observe the account on.
    ///   - store: The type of the store that observes the account.
    /// - Returns: A view that observes the account.
    func observation<Store: AccountObserving>(of account: Account, on network: Network,
                                              in store: Store.Type) -> some View {
        modifier(AccountObservation<Store>(account: account, network: network))
    }
}
