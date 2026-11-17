import Privacy
import RPC
import Testing
@testable import widgets

extension PrivateBalances {
    func settledBalance(of account: widgets.Account, on network: Network) async throws -> UInt64 {
        let settled: UInt64? = try await poll {
            let status = try await refresh(account, on: network)
            guard status != .unregistered else { return 0 }
            guard let balance = status.balance(of: .nativeSOL), balance.pending == 0 else { return nil }
            return balance.available
        }
        return try #require(settled, "The indexer didn't report the recorded transactions within a minute.")
    }
}
