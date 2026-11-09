import RPC
import Testing
@testable import widgets

extension PrivateBalances {
    func settledBalance(of account: widgets.Account, on network: Network) async throws -> UInt64 {
        let settled: UInt64? = try await poll {
            switch try await refresh(account, on: network) {
            case .unregistered: 0
            case .balance(let available, pending: 0): available
            default: nil
            }
        }
        return try #require(settled, "The indexer didn't report the recorded transactions within a minute.")
    }
}
