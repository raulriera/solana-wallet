import Vault
import Wallet
@testable import widgets

extension PrivateBalances {
    /// Creates private balances over in-memory stores, with each network's production provider client sending its
    /// requests to local responses.
    /// - Parameters:
    ///   - keys: Each account's keys.
    ///   - notes: Each account's notes on each network.
    ///   - codes: Each account's redeem codes on each network; empty storage by default.
    ///   - recovery: The recovery storage that enabling reads.
    ///   - responses: The local responses that every network's provider client sends requests to.
    ///   - provider: The selected provider; Helius by default.
    /// - Returns: Private balances whose requests never leave the process.
    static func inMemory(keys: StoredValue<Keys>, notes: StoredValue<Notes>, codes: StoredValue<Codes> = StoredValue(),
                         recovery: any RecoveryStoring,
                         responses: HTTPResponses, provider: ProviderSettings.Provider = .helius) -> PrivateBalances {
        PrivateBalances(recovery: recovery, wallet: Wallet(), keys: keys, notes: notes, codes: codes) { network in
            responses.providerClient(network: network, settings: StoredValue(ProviderSettings(selection: provider)),
                                     providerKey: StoredValue("fixture-key"))
        }
    }
}
