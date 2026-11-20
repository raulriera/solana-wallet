import Foundation
import RPC
import Transactions

/// A sent transaction's public facts: who sent it on which network, what it does, and how it settled.
///
/// Only the facts that find the transaction again are saved. The status and the settled date last for one launch.
nonisolated struct TransactionRecord: Codable, Identifiable, Equatable, Sendable {
    /// The account and network whose records are kept together.
    struct Key: Hashable, Sendable {
        let account: UUID
        let network: Network
    }

    /// What a transaction does.
    enum Kind: String, Codable, Sendable {
        case payment
        /// A move of the account's public asset into its private balance.
        case privateDeposit
        /// A move of the account's private asset to its own public balance.
        case privateWithdrawal
    }

    /// Whether a transaction settled, and how.
    enum Status: Sendable {
        case pending
        case succeeded
        /// The transaction landed and failed.
        case failed
        /// The transaction can never land.
        case dropped
    }

    /// The identifier of the account that sent the transaction.
    let account: UUID
    let network: Network
    let kind: Kind
    /// The transaction's first signature, which identifies it.
    let signature: String
    let lastValidBlockHeight: UInt64
    var status = Status.pending
    /// When the transaction's outcome was found, or `nil` while it's pending.
    var settled: Date?

    var id: String { signature }

    var key: Key { Key(account: account, network: network) }

    var submission: Submission {
        Submission(signature: signature, network: network, lastValidBlockHeight: lastValidBlockHeight)
    }

    /// Creates a pending record of a sent transaction.
    ///
    /// - Parameters:
    ///   - kind: What the transaction does.
    ///   - account: The identifier of the account that sent it.
    ///   - submission: The transaction's receipt.
    init(_ kind: Kind, from account: UUID, submission: Submission) {
        self.account = account
        network = submission.network
        self.kind = kind
        signature = submission.signature
        lastValidBlockHeight = submission.lastValidBlockHeight
    }

    /// The saved facts.
    private enum CodingKeys: String, CodingKey {
        case account, network, kind, signature, lastValidBlockHeight
    }
}

nonisolated extension TransactionRecord.Status {
    /// Creates the status of a transaction whose outcome was found.
    ///
    /// - Parameter outcome: The transaction's outcome.
    init(_ outcome: Confirmation.Outcome) {
        self = switch outcome {
        case .succeeded: .succeeded
        case .failed: .failed
        case .dropped: .dropped
        }
    }
}
