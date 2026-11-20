import Foundation
import RPC
import Transactions

/// A sent transaction's public facts: who sent it on which network, what it does, and how it settled.
nonisolated struct TransactionRecord: Codable, Identifiable, Equatable, Sendable {
    /// The account and network whose records are kept together.
    struct Key: Hashable, Codable, Sendable {
        let account: UUID
        let network: Network

        /// The key's persisted field names.
        private enum CodingKeys: String, CodingKey {
            case account, network
        }
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
    enum Status: String, Codable, Sendable {
        case pending
        case succeeded
        /// The transaction landed and failed.
        case failed
        /// The transaction can never land.
        case dropped
    }

    let key: Key
    let kind: Kind
    /// The transaction's first signature, which identifies it.
    let signature: String
    let lastValidBlockHeight: UInt64
    var status: Status
    /// When the transaction was sent.
    let created: Date
    /// When the transaction's outcome was found, or `nil` while it's pending.
    var settled: Date?

    var id: String { signature }

    var submission: Submission {
        Submission(signature: signature, network: key.network, lastValidBlockHeight: lastValidBlockHeight)
    }

    /// Creates a pending record of a sent transaction.
    ///
    /// - Parameters:
    ///   - kind: What the transaction does.
    ///   - account: The identifier of the account that sent it.
    ///   - submission: The transaction's receipt.
    ///   - created: When the transaction was sent.
    init(_ kind: Kind, from account: UUID, submission: Submission, created: Date) {
        key = Key(account: account, network: submission.network)
        self.kind = kind
        signature = submission.signature
        lastValidBlockHeight = submission.lastValidBlockHeight
        status = .pending
        self.created = created
    }

    /// The record's persisted field names.
    private enum CodingKeys: String, CodingKey {
        case account, network, kind, signature, lastValidBlockHeight, status, created, settled
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = Key(account: try container.decode(UUID.self, forKey: .account),
                  network: try container.decode(Network.self, forKey: .network))
        kind = try container.decode(Kind.self, forKey: .kind)
        signature = try container.decode(String.self, forKey: .signature)
        lastValidBlockHeight = try container.decode(UInt64.self, forKey: .lastValidBlockHeight)
        status = try container.decode(Status.self, forKey: .status)
        created = try container.decode(Date.self, forKey: .created)
        settled = try container.decodeIfPresent(Date.self, forKey: .settled)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(key.account, forKey: .account)
        try container.encode(key.network, forKey: .network)
        try container.encode(kind, forKey: .kind)
        try container.encode(signature, forKey: .signature)
        try container.encode(lastValidBlockHeight, forKey: .lastValidBlockHeight)
        try container.encode(status, forKey: .status)
        try container.encode(created, forKey: .created)
        try container.encodeIfPresent(settled, forKey: .settled)
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
