import RPC
import Testing
@testable import widgets

/// Private balances whose deletion the shared reset storage records in order.
struct ResetPrivateBalances: PrivateBalancing {
    /// The storage that records every reset step.
    let storage: ResetStorage

    /// Reports any enabling, because a reset only deletes.
    /// - Parameters:
    ///   - account: The account the caller tried to enable.
    ///   - network: The network the caller named.
    func enable(_ account: widgets.Account, on network: Network) async throws {
        Issue.record("A reset must not turn on private balances.")
    }

    /// Reports any refresh, because a reset only deletes.
    /// - Parameters:
    ///   - account: The account the caller tried to refresh.
    ///   - network: The network the caller named.
    /// - Returns: ``PrivateBalanceStatus/off``.
    func refresh(_ account: widgets.Account, on network: Network) async throws -> PrivateBalanceStatus {
        Issue.record("A reset must not refresh private balances.")
        return .off
    }

    /// Reports any preparation, because a reset only deletes.
    /// - Parameters:
    ///   - request: The transaction the caller asked for.
    ///   - account: The account the caller named.
    ///   - network: The network the caller named.
    /// - Returns: Never; it throws.
    /// - Throws: `CancellationError` after reporting the issue.
    func prepare(_ request: PrivateTransactionRequest, from account: widgets.Account, on network: Network) async throws
        -> PreparedPrivateTransaction {
        Issue.record("A reset must not prepare private transactions.")
        throw CancellationError()
    }

    /// Reports any completion, because a reset only deletes.
    /// - Parameters:
    ///   - transaction: The transaction the caller completed.
    ///   - confirmation: Its outcome.
    /// - Returns: ``PrivateBalanceStatus/off``.
    func complete(_ transaction: PreparedPrivateTransaction, with confirmation: widgets.Confirmation) async throws
        -> PrivateBalanceStatus {
        Issue.record("A reset must not record private transactions.")
        return .off
    }

    /// Records the deletion, unless this step fails.
    /// - Throws: A scripted failure.
    func removeAll() async throws { try await storage.delete(.privateBalances) }
}
