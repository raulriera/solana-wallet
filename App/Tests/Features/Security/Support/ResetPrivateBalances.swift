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

    /// Records the deletion, unless this step fails.
    /// - Throws: A scripted failure.
    func removeAll() async throws { try await storage.delete(.privateBalances) }
}
