import Foundation
import Observation
import Portfolio
import RPC

/// A Portfolio tab's private-balance workflows: turning private balances on and opening balance moves.
@MainActor
@Observable
final class PrivateBalanceModel {
    /// The error of the last attempt to turn private balances on.
    var error: PrivateBalanceError?
    /// The attempt to turn private balances on that's waiting or running.
    private(set) var attempt: UUID?
    /// Whether the last attempt turned private balances on for its account.
    private(set) var isTurnedOn = false
    /// The open balance move, or `nil` when none is open.
    var move: BalanceMove?

    var isTurningOn: Bool { attempt != nil }

    /// Opens a move of a holding's asset between an account's balances, unless one is open.
    ///
    /// - Parameters:
    ///   - direction: Which balance the asset leaves, and which one it reaches.
    ///   - holding: The account's public holding of the asset.
    ///   - privateBalances: The store of every account's private balance.
    ///   - account: The account whose asset moves.
    ///   - network: The network the asset moves on.
    func open(
        _ direction: BalanceMoveProposal.Direction,
        of holding: Holding,
        in privateBalances: PrivateBalanceStore,
        for account: Account,
        on network: Network
    ) {
        guard move == nil else { return }
        move = privateBalances.move(direction, of: holding, for: account, on: network)
    }

    /// Asks to turn private balances on, unless an attempt is already waiting or running.
    func turnOn() {
        guard attempt == nil else { return }
        error = nil
        isTurnedOn = false
        attempt = UUID()
    }

    /// Turns private balances on for an attempt that's still current.
    ///
    /// - Parameters:
    ///   - attempt: The attempt to run.
    ///   - privateBalances: The store of every account's private balance.
    ///   - account: The account to turn private balances on for.
    ///   - network: The network to turn private balances on for.
    func run(_ attempt: UUID?, in privateBalances: PrivateBalanceStore, for account: Account,
             on network: Network) async {
        guard let attempt, self.attempt == attempt else { return }
        defer { if self.attempt == attempt { self.attempt = nil } }
        do {
            try await privateBalances.turnOn(account, on: network)
            guard self.attempt == attempt else { return }
            isTurnedOn = true
        } catch is CancellationError {
        } catch {
            guard self.attempt == attempt else { return }
            self.error = error as? PrivateBalanceError ?? .turnOnFailed
        }
    }
}
