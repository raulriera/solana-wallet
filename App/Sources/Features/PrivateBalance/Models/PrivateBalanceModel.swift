import Foundation
import Observation
import Portfolio
import RPC

/// A Portfolio tab's private-balance workflows: turning private balances on and opening balance moves.
@MainActor
@Observable
final class PrivateBalanceModel {
    /// A sheet that the private balance presents.
    enum Sheet: Identifiable {
        case move(BalanceMove)
        /// The choice of who to send the private balance to.
        case recipients

        /// The move's identifier, or `nil` for the choice of recipient.
        var id: ObjectIdentifier? {
            move?.id
        }

        /// The open balance move, or `nil` for the choice of recipient.
        var move: BalanceMove? {
            guard case .move(let move) = self else { return nil }
            return move
        }
    }

    /// The error of the last attempt to turn private balances on.
    var error: PrivateBalanceError?
    /// The attempt to turn private balances on that's waiting or running.
    private(set) var attempt: UUID?
    /// Whether the last attempt turned private balances on for its account.
    private(set) var isTurnedOn = false
    /// The open sheet, or `nil` when none is open.
    var sheet: Sheet?

    var isTurningOn: Bool { attempt != nil }

    /// Opens a move of a holding's asset between an account's balances, unless a sheet is open.
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
        guard sheet == nil else { return }
        sheet = privateBalances.move(direction, of: holding, for: account, on: network).map(Sheet.move)
    }

    /// Opens the choice of who to send the private balance to, unless a sheet is open.
    func openRecipients() {
        guard sheet == nil else { return }
        sheet = .recipients
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
