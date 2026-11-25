import Foundation
import RPC
import Transactions

/// A sent transaction's public facts: who sent it, what it does, the transaction as reviewed, and its outcome.
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
    /// The transaction as reviewed, with the message that was signed and sent.
    let transaction: Transaction
    private(set) var outcome: Outcome
    /// When the transaction's settled status was found, or `nil` while it's pending.
    private(set) var settled: Date?

    var id: String { outcome.signature }

    var network: Network { outcome.network }

    var isPending: Bool { outcome.status == .pending }

    var key: Key { Key(account: account, network: network) }

    /// Creates a pending record of a sent transaction.
    ///
    /// - Parameters:
    ///   - kind: What the transaction does.
    ///   - account: The identifier of the account that sent it.
    ///   - transaction: The transaction as reviewed.
    ///   - outcome: The transaction's pending outcome.
    init(_ kind: Kind, from account: UUID, transaction: Transaction, outcome: Outcome) {
        self.account = account
        self.kind = kind
        self.transaction = transaction
        self.outcome = outcome
    }

    /// Records how the transaction settled.
    ///
    /// - Parameters:
    ///   - status: The transaction's settled status.
    ///   - date: When the status was found.
    mutating func settle(_ status: Outcome.Status, at date: Date) {
        outcome = outcome.settled(status)
        settled = date
    }
}
