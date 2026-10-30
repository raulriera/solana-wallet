import Foundation
import Observation
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

    /// Opens a move of an account's SOL between its balances, unless one is open.
    ///
    /// - Parameters:
    ///   - direction: Which balance the SOL leaves, and which one it reaches.
    ///   - publicLamports: The account's public SOL, in lamports.
    ///   - privateBalances: The store of every account's private balance.
    ///   - account: The account whose SOL moves.
    ///   - network: The network the SOL moves on.
    func open(_ direction: BalanceMoveProposal.Direction, publicLamports: UInt64,
              in privateBalances: PrivateBalanceStore, for account: Account, on network: Network) {
        guard move == nil else { return }
        move = privateBalances.move(direction, publicLamports: publicLamports, for: account, on: network)
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
