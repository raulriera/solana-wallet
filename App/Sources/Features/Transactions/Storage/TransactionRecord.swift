import Foundation
import RPC

/// A sent transaction's public facts: who sent it, what it does, and its outcome.
nonisolated struct TransactionRecord: Codable, Identifiable, Equatable, Sendable {
    /// The account and network whose records are kept together.
    struct Key: Hashable, Sendable {
        let account: UUID
        let network: Network
    }

    /// What a transaction does.
    enum Kind: String, Codable, Sendable {
        case payment
        /// A payment from the account's private balance to a recipient's private balance.
        case privatePayment
        /// A move of the account's public asset into its private balance.
        case privateDeposit
        /// A move of the account's private asset to its own public balance.
        case privateWithdrawal
    }

    /// The identifier of the account that sent the transaction.
    let account: UUID
    let kind: Kind
    private(set) var outcome: TransactionOutcome
    /// When the transaction's settled status was found, or `nil` while it's pending.
    private(set) var settled: Date?

    var id: String { outcome.signature }

    var key: Key { Key(account: account, network: outcome.network) }

    /// Creates a pending record of a sent transaction.
    ///
    /// - Parameters:
    ///   - kind: What the transaction does.
    ///   - account: The identifier of the account that sent it.
    ///   - outcome: The transaction's pending outcome.
    init(_ kind: Kind, from account: UUID, outcome: TransactionOutcome) {
        self.account = account
        self.kind = kind
        self.outcome = outcome
    }

    /// Records how the transaction settled.
    ///
    /// - Parameters:
    ///   - status: The transaction's settled status.
    ///   - date: When the status was found.
    mutating func settle(_ status: TransactionOutcome.Status, at date: Date) {
        outcome = outcome.settled(status)
        settled = date
    }
}
