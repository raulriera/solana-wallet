import Vault
import Wallet
@testable import widgets

extension PrivateBalances {
    @MainActor
    static func inMemory(keys: StoredValue<Keys>, notes: StoredValue<Notes>, codes: StoredValue<Codes> = StoredValue(),
                         recovery: any RecoveryStoring,
                         responses: HTTPResponses, provider: RPCSettings.Provider = .helius) -> PrivateBalances {
        let rpcStore = RPCStore.inMemory(selection: provider, key: "fixture-key")
        return PrivateBalances(recovery: recovery, wallet: Wallet(), keys: keys, notes: notes,
                               codes: codes) { network in
            responses.rpcProvider(network: network, rpcStore: rpcStore)
        }
    }
}
