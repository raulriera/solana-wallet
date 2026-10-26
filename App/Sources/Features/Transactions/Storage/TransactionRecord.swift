import Foundation
import RPC
import Transactions

/// A sent transaction's public facts: who sent it on which network, what it does, and how it settled.
///
/// A record holds no keys and no signed bytes. Its persisted names are permanent, so saved records stay readable.
nonisolated struct TransactionRecord: Codable, Identifiable, Equatable, Sendable {
    /// The account and network whose records are kept together.
    struct Key: Hashable, Codable, Sendable {
        /// The identifier of the account that sent the transaction.
        let account: UUID
        /// The network that the transaction was sent on.
        let network: Network

        /// The key's persisted names, which never change.
        private enum CodingKeys: String, CodingKey {
            case account, network
        }
    }

    /// What a transaction does.
    enum Kind: Equatable, Sendable {
        /// A payment of SOL or a token to a recipient.
        case payment(recipient: Address, mint: Address?, units: UInt64)
        /// A move of the account's public SOL into its private balance.
        case privateDeposit(lamports: UInt64)
        /// A move of the account's private SOL to its own public address.
        case privateWithdrawal(lamports: UInt64)

        /// The address that a payment went to, or `nil` for a move between the account's own balances.
        var recipient: Address? {
            guard case .payment(let recipient, _, _) = self else { return nil }
            return recipient
        }
    }

    /// Whether a transaction settled, and how.
    enum Status: String, Codable, Sendable {
        /// The transaction was sent, and its outcome isn't known yet.
        case pending
        /// The transaction landed without an error.
        case succeeded
        /// The transaction landed and failed; it paid its network fee and changed nothing else.
        case failed
        /// The transaction can never land, so nothing left the account.
        case dropped
    }

    /// The account and network that the transaction belongs to.
    let key: Key
    /// What the transaction does.
    let kind: Kind
    /// The transaction's first signature, which identifies it on the network.
    let signature: String
    /// The last block height at which the transaction's blockhash is valid.
    let lastValidBlockHeight: UInt64
    /// Whether the transaction settled, and how.
    var status: Status
    /// When the transaction was sent.
    let created: Date
    /// When the transaction's outcome was found, or `nil` while it's pending.
    var settled: Date?

    /// Identifies the record by its transaction's signature.
    var id: String { signature }

    /// The receipt that a watch of the transaction follows.
    var submission: Submission {
        Submission(signature: signature, network: key.network, lastValidBlockHeight: lastValidBlockHeight)
    }

    /// Creates a pending record of a transaction that was just sent.
    /// - Parameters:
    ///   - kind: What the transaction does.
    ///   - account: The identifier of the account that sent it.
    ///   - submission: The transaction's signature, network, and blockhash expiry.
    ///   - created: When the transaction was sent.
    init(_ kind: Kind, from account: UUID, submission: Submission, created: Date) {
        key = Key(account: account, network: submission.network)
        self.kind = kind
        signature = submission.signature
        lastValidBlockHeight = submission.lastValidBlockHeight
        status = .pending
        self.created = created
    }

    /// The record's persisted names, which never change.
    private enum CodingKeys: String, CodingKey {
        case account, network, kind, recipient, mint, units, lamports, signature, lastValidBlockHeight, status, created,
             settled
    }

    /// The persisted name of each kind, which never changes.
    private enum KindName: String, Codable {
        case payment, privateDeposit, privateWithdrawal
    }

    /// Reads a saved record, whose kind's details sit beside its other facts.
    /// - Parameter decoder: The decoder that supplies the saved record.
    /// - Throws: A decoding error for a missing fact, an unknown kind or status, or an invalid address.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = Key(account: try container.decode(UUID.self, forKey: .account),
                  network: try container.decode(Network.self, forKey: .network))
        kind = switch try container.decode(KindName.self, forKey: .kind) {
        case .payment:
            .payment(recipient: try container.decode(Address.self, forKey: .recipient),
                     mint: try container.decodeIfPresent(Address.self, forKey: .mint),
                     units: try container.decode(UInt64.self, forKey: .units))
        case .privateDeposit: .privateDeposit(lamports: try container.decode(UInt64.self, forKey: .lamports))
        case .privateWithdrawal: .privateWithdrawal(lamports: try container.decode(UInt64.self, forKey: .lamports))
        }
        signature = try container.decode(String.self, forKey: .signature)
        lastValidBlockHeight = try container.decode(UInt64.self, forKey: .lastValidBlockHeight)
        status = try container.decode(Status.self, forKey: .status)
        created = try container.decode(Date.self, forKey: .created)
        settled = try container.decodeIfPresent(Date.self, forKey: .settled)
    }

    /// Saves the record with its kind's details beside its other facts.
    /// - Parameter encoder: The encoder that receives the record.
    /// - Throws: An encoding error.
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(key.account, forKey: .account)
        try container.encode(key.network, forKey: .network)
        switch kind {
        case .payment(let recipient, let mint, let units):
            try container.encode(KindName.payment, forKey: .kind)
            try container.encode(recipient, forKey: .recipient)
            try container.encodeIfPresent(mint, forKey: .mint)
            try container.encode(units, forKey: .units)
        case .privateDeposit(let lamports):
            try container.encode(KindName.privateDeposit, forKey: .kind)
            try container.encode(lamports, forKey: .lamports)
        case .privateWithdrawal(let lamports):
            try container.encode(KindName.privateWithdrawal, forKey: .kind)
            try container.encode(lamports, forKey: .lamports)
        }
        try container.encode(signature, forKey: .signature)
        try container.encode(lastValidBlockHeight, forKey: .lastValidBlockHeight)
        try container.encode(status, forKey: .status)
        try container.encode(created, forKey: .created)
        try container.encodeIfPresent(settled, forKey: .settled)
    }
}

nonisolated extension TransactionRecord.Status {
    /// The status of a transaction whose outcome was found.
    /// - Parameter outcome: Whether the transaction succeeded, failed, or was dropped.
    init(_ outcome: Confirmation.Outcome) {
        self = switch outcome {
        case .succeeded: .succeeded
        case .failed: .failed
        case .dropped: .dropped
        }
    }
}
