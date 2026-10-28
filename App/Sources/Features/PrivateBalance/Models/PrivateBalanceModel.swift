import Foundation
import Observation
import RPC

/// One window's private-balance workflows on its network: turning private balances on for an account, and opening
/// moves of SOL between the account's balances.
///
/// The balances themselves come from the shared ``PrivateBalanceStore``. Turning private balances on runs once per
/// attempt in the scene's task and reports a typed error, except when the person cancels authentication.
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
    /// The window's network.
    private let network: Network
    private let store: PrivateBalanceStore

    /// Whether an attempt to turn private balances on is waiting or running.
    var isTurningOn: Bool { attempt != nil }

    /// Creates a model with no attempt or move.
    /// - Parameters:
    ///   - store: The private balance of every account on every network, which moves prepare, complete, and send
    ///     through.
    ///   - network: The window's network.
    init(store: PrivateBalanceStore, network: Network) {
        self.store = store
        self.network = network
    }

    /// Opens a move of an account's SOL between its balances, while private balances are on; a withdrawal opens only
    /// while some private SOL is available.
    /// - Parameters:
    ///   - direction: Which balance the SOL leaves, and which one it reaches.
    ///   - publicLamports: The account's public SOL, in lamports, which a deposit can add.
    ///   - account: The window's account.
    func open(_ direction: BalanceMoveProposal.Direction, publicLamports: UInt64, for account: Account) {
        guard move == nil else { return }
        move = store.move(direction, publicLamports: publicLamports, for: account, on: network)
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
    ///   - account: The window's account.
    func run(_ attempt: UUID?, for account: Account) async {
        guard let attempt, self.attempt == attempt else { return }
        defer { if self.attempt == attempt { self.attempt = nil } }
        do {
            try await store.turnOn(account, on: network)
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
