import RPC
import Testing
@testable import widgets

struct ResetPrivateBalances: PrivateBalancing {
    let storage: ResetStorage

    func enable(_ account: widgets.Account, on network: Network) async throws {
        Issue.record("A reset must not turn on private balances.")
    }

    func refresh(_ account: widgets.Account, on network: Network) async throws -> PrivateBalanceStatus {
        Issue.record("A reset must not refresh private balances.")
        return .off(isRegistered: false)
    }

    func savedStatus(of account: widgets.Account, on network: Network) async throws -> PrivateBalanceStatus? {
        Issue.record("A reset must not read saved private balances.")
        return nil
    }

    func prepare(_ request: PrivateTransactionRequest, from account: widgets.Account, on network: Network) async throws
        -> PreparedPrivateTransaction {
        Issue.record("A reset must not prepare private transactions.")
        throw CancellationError()
    }

    func complete(_ transaction: PreparedPrivateTransaction, with confirmation: widgets.Confirmation) async throws
        -> PrivateBalanceStatus {
        Issue.record("A reset must not record private transactions.")
        return .off(isRegistered: false)
    }

    func outstandingCodes(of account: widgets.Account, on network: Network) async throws -> [OutstandingRedeemCode] {
        Issue.record("A reset must not list redeem codes.")
        return []
    }

    func removeAll() async throws { try await storage.delete(.privateBalances) }
}
