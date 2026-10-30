import Vault
import Wallet
@testable import widgets

extension PrivateBalances {
    @MainActor
    static func inMemory(keys: StoredValue<Keys>, notes: StoredValue<Notes>, codes: StoredValue<Codes> = StoredValue(),
                         recovery: any RecoveryStoring,
                         responses: HTTPResponses, provider: ProviderSettings.Provider = .helius) -> PrivateBalances {
        let providers = ProviderStore.inMemory(selection: provider, key: "fixture-key")
        return PrivateBalances(recovery: recovery, wallet: Wallet(), keys: keys, notes: notes,
                               codes: codes) { network in
            responses.providerClient(network: network, providers: providers)
        }
    }
}
