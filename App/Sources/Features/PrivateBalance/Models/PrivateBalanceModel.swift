import Foundation
import Observation
import RPC
import Wallet

/// One window's private balance of its account on its network, and turning private balances on for that account.
///
/// A refresh shows the account's last read balance, or why it has none; a failed refresh keeps what was read before.
/// Accounts whose path has no private-balance keys show nothing. Turning private balances on runs once per attempt in
/// the scene's task and reports a typed error, except when the person cancels authentication.
@MainActor
@Observable
final class PrivateBalanceModel {
    /// The account's last read balance, or why it has none; `nil` before the first read, or for an account without
    /// private-balance keys.
    private(set) var status: PrivateBalanceStatus? {
        didSet { hasBalance = Self.holdsSOL(status) }
    }
    /// Whether the account holds any private SOL, available or pending; kept apart from ``status`` so the token list
    /// changes only when this does.
    private(set) var hasBalance = false
    /// The error of the last attempt to turn private balances on.
    var error: PrivateBalanceError?
    /// The attempt to turn private balances on that's waiting for the scene's task, or running.
    private(set) var attempt: UUID?
    /// Whether the last attempt turned private balances on for the account.
    private(set) var isTurnedOn = false
    private var account: Account?
    private let balances: any PrivateBalancing
    private let network: Network

    /// Whether an attempt to turn private balances on is waiting or running.
    var isTurningOn: Bool { attempt != nil }

    /// Creates a model that shows nothing until its first refresh.
    /// - Parameters:
    ///   - balances: The private balances of every account.
    ///   - network: The window's network.
    init(balances: any PrivateBalancing, network: Network) {
        self.balances = balances
        self.network = network
    }

    /// Reads an account's private balance, starting over when the account differs from the last one.
    /// - Parameter account: The window's account.
    func refresh(for account: Account) async {
        if self.account != account {
            self.account = account
            status = nil
            error = nil
            attempt = nil
            isTurnedOn = false
        }
        await refresh()
    }

    /// Reads the current account's private balance again; a failed read keeps the balance read before.
    func refresh() async {
        guard let account, account.path.hasPrivateBalanceKeys else { return }
        guard let status = try? await balances.refresh(account, on: network), self.account == account else { return }
        self.status = status
    }

    /// Asks to turn private balances on for the current account, unless an attempt is already waiting or running.
    func turnOn() {
        guard attempt == nil, account != nil else { return }
        error = nil
        attempt = UUID()
    }

    /// Turns private balances on once in the scene's SwiftUI-managed task, then reads the balance.
    /// - Parameter attempt: The identifier that the scene's task captured.
    func run(_ attempt: UUID?) async {
        guard let attempt, self.attempt == attempt, let account else { return }
        defer { if self.attempt == attempt { self.attempt = nil } }
        do {
            try await balances.enable(account, on: network)
            let status = try await balances.refresh(account, on: network)
            guard self.attempt == attempt, self.account == account else { return }
            self.status = status
            isTurnedOn = true
        } catch is CancellationError {
            // The person dismissed authentication, or the scene left.
        } catch {
            guard self.attempt == attempt else { return }
            self.error = error as? PrivateBalanceError ?? .turnOnFailed
        }
    }

    /// Whether a status holds any private SOL.
    /// - Parameter status: A read status, or `nil` before the first read.
    /// - Returns: Whether the balance's available or pending SOL is above zero.
    private static func holdsSOL(_ status: PrivateBalanceStatus?) -> Bool {
        guard case .balance(let available, let pending) = status else { return false }
        return available > 0 || pending > 0
    }
}
