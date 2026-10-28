import Foundation
import Observation
import RPC

/// One Portfolio tab's private-balance workflows: turning private balances on for an account, and opening moves of
/// SOL between the account's balances.
///
/// The balances themselves come from the shared ``PrivateBalanceStore``, which each call receives with the account and
/// network it acts on. Turning private balances on runs once per attempt in the scene's task and reports a typed
/// error, except when the person cancels authentication.
@MainActor
@Observable
final class PrivateBalanceModel {
    /// The error of the last attempt to turn private balances on.
    var error: PrivateBalanceError?
    /// The attempt to turn private balances on that's waiting for the scene's task, or running.
    private(set) var attempt: UUID?
    /// Whether the last attempt turned private balances on for its account.
    private(set) var isTurnedOn = false
    /// The open move of the account's SOL between its public and private balances.
    var move: BalanceMove?

    /// Whether an attempt to turn private balances on is waiting or running.
    var isTurningOn: Bool { attempt != nil }

    /// Opens a move of an account's SOL between its balances, while private balances are on; a withdrawal opens only
    /// while some private SOL is available.
    /// - Parameters:
    ///   - direction: Which balance the SOL leaves, and which one it reaches.
    ///   - publicLamports: The account's public SOL, in lamports, which a deposit can add.
    ///   - privateBalances: The private balance of every account on every network, which prepares the move.
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
        // Each attempt that succeeds changes this again, so its haptic and announcement follow.
        isTurnedOn = false
        attempt = UUID()
    }

    /// Turns private balances on once in the scene's SwiftUI-managed task; the shared store then shows the balance.
    /// - Parameters:
    ///   - attempt: The identifier that the scene's task captured.
    ///   - privateBalances: The private balance of every account on every network, which turns private balances on.
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
            // The person dismissed authentication, or the scene left.
        } catch {
            guard self.attempt == attempt else { return }
            self.error = error as? PrivateBalanceError ?? .turnOnFailed
        }
    }
}
