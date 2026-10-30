import Foundation
import ModularArithmetic
public import RPC
import Transactions

/// An account's unspent notes, its pending amounts, and where its next read of the indexer resumes.
public struct NoteSyncState: Sendable, Equatable, Codable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// An error in a state's amounts.
    public enum ValidationError: Error, Equatable {
        /// The notes and pending amounts total more lamports than a 64-bit integer holds.
        case amountOverflow
    }

    /// The keys of a state's encoded fields.
    private enum CodingKeys: String, CodingKey {
        case position, notes, outputTreeID, pending, localSpends
    }

    /// The length of a nullifier, in bytes.
    private static let nullifierLength = 32

    /// Where the next read resumes, or `nil` before the first sync.
    let position: NoteSyncPosition?

    /// The unspent notes, in slot, signature, leaf, and tree order.
    public let notes: [ReceivedNote]

    /// The ID of the tree that receives new outputs, or `nil` if no sync reported one.
    public let outputTreeID: UInt16?

    let pending: [PendingAmount]

    /// The nullifiers of recorded spends whose notes a sync returned before it reported the spend.
    let localSpends: Set<[UInt8]>

    /// The total of the unspent notes and the pending amounts, in lamports.
    public var lamports: UInt64 {
        notes.reduce(0) { $0 + $1.lamports } + pendingLamports
    }

    public var pendingLamports: UInt64 {
        pending.reduce(0) { $0 + $1.lamports }
    }

    public var description: String { "NoteSyncState" }

    public var debugDescription: String { description }

    public var customMirror: Mirror { Mirror(self, children: [:]) }

    /// Creates the state of an account that hasn't synced.
    public init() {
        position = nil
        notes = []
        outputTreeID = nil
        pending = []
        localSpends = []
    }

    /// Creates a state and checks that its total fits a 64-bit integer.
    ///
    /// - Parameters:
    ///   - position: Where the next read resumes.
    ///   - notes: The unspent notes.
    ///   - outputTreeID: The ID of the tree that receives new outputs, if known.
    ///   - pending: The pending amounts.
    ///   - localSpends: The nullifiers of recorded spends to keep hiding.
    /// - Throws: ``ValidationError/amountOverflow`` if the total exceeds a 64-bit integer.
    init(
        position: NoteSyncPosition?,
        notes: [ReceivedNote],
        outputTreeID: UInt16?,
        pending: [PendingAmount],
        localSpends: Set<[UInt8]>
    ) throws {
        _ = try (notes.map(\.lamports) + pending.map(\.lamports)).reduce(UInt64(0)) { total, lamports in
            let (sum, overflow) = total.addingReportingOverflow(lamports)
            guard !overflow else { throw ValidationError.amountOverflow }
            return sum
        }
        self.position = position
        self.notes = notes
        self.outputTreeID = outputTreeID
        self.pending = pending
        self.localSpends = localSpends
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let position = try container.decodeIfPresent(NoteSyncPosition.self, forKey: .position)
        let notes = try container.decode([ReceivedNote].self, forKey: .notes)
        let outputTreeID = try container.decode(UInt16?.self, forKey: .outputTreeID)
        let pending = try container.decode([PendingAmount].self, forKey: .pending)
        let localSpends = try container.decode([Data].self, forKey: .localSpends).map { [UInt8]($0) }
        guard localSpends.allSatisfy({ $0.count == Self.nullifierLength }) else {
            throw DecodingError.dataCorruptedError(forKey: .localSpends, in: container, debugDescription: "A nullifier has 32 bytes.")
        }
        do {
            try self.init(position: position, notes: notes, outputTreeID: outputTreeID, pending: pending, localSpends: Set(localSpends))
        } catch {
            throw DecodingError.dataCorruptedError(forKey: .notes, in: container, debugDescription: "The total overflows.")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(position, forKey: .position)
        try container.encode(notes, forKey: .notes)
        try container.encode(outputTreeID, forKey: .outputTreeID)
        try container.encode(pending, forKey: .pending)
        try container.encode(localSpends.sorted { $0.lexicographicallyPrecedes($1) }.map { Data($0) }, forKey: .localSpends)
    }

    /// Records a spend's successful transaction.
    ///
    /// - Parameters:
    ///   - spend: The spend whose transaction succeeded.
    ///   - signature: The transaction's signature.
    /// - Returns: The state without the spent notes and with the spend's received lamports pending.
    /// - Throws: ``ValidationError/amountOverflow`` if the total would exceed a 64-bit integer.
    public func recording(_ spend: PrivateSpend, signature: String) throws -> NoteSyncState {
        let spent = Set(spend.nullifiers.map(\.bigEndianBytes))
        let isHeld = notes.contains { spent.contains($0.nullifier.bigEndianBytes) }
        return try NoteSyncState(
            position: position, notes: notes.filter { !spent.contains($0.nullifier.bigEndianBytes) }, outputTreeID: outputTreeID,
            pending: isHeld ? pending(adding: spend.receivedLamports, signature: signature) : pending,
            localSpends: localSpends.union(spent)
        )
    }

    /// Records a deposit's successful transaction to the account.
    ///
    /// - Parameters:
    ///   - lamports: The deposited amount.
    ///   - signature: The transaction's signature.
    /// - Returns: The state with the deposit pending.
    /// - Throws: ``Transactions/ValidationError/invalidAmount`` for zero lamports, or
    ///   ``ValidationError/amountOverflow`` if the total would exceed a 64-bit integer.
    public func recording(depositOf lamports: UInt64, signature: String) throws -> NoteSyncState {
        guard lamports > 0 else { throw Transactions.ValidationError.invalidAmount }
        return try NoteSyncState(
            position: position, notes: notes, outputTreeID: outputTreeID, pending: pending(adding: lamports, signature: signature),
            localSpends: localSpends
        )
    }

    /// Adds a recorded transaction's lamports to the pending amounts unless they're zero or already counted.
    ///
    /// - Parameters:
    ///   - lamports: The lamports that the transaction gave the account.
    ///   - signature: The transaction's signature.
    /// - Returns: The pending amounts.
    private func pending(adding lamports: UInt64, signature: String) -> [PendingAmount] {
        let isCounted = notes.contains { $0.signature == signature } || pending.contains { $0.signature == signature }
        return lamports == 0 || isCounted ? pending : pending + [PendingAmount(signature: signature, lamports: lamports)]
    }

    /// Reads the indexer for the account's new notes and spends and returns the next state.
    ///
    /// - Parameters:
    ///   - account: The account of this state.
    ///   - provider: The indexer of the account's network.
    /// - Returns: The state with the unspent notes and the position of the next read.
    /// - Throws: ``ValidationError/amountOverflow`` if the total exceeds a 64-bit integer, a
    ///   ``RPC/PrivateNoteError`` if the position came from other view tags, a cipher or key agreement
    ///   error, or a request, transport, response, or cancellation error.
    @concurrent
    public func synced(for account: ShieldedAccount, using provider: some PrivateNoteProviding) async throws -> NoteSyncState {
        let (position, notes, localSpends, tags) = (position, notes, localSpends, account.viewTags)
        let (batch, received, respent, spent) = try await withThrowingTaskGroup(of: SyncRead.self) { group in
            group.addTask {
                .tagged(try await provider.shieldedTransactions(taggedWith: tags, after: position))
            }
            Self.readSpends(of: notes, into: &group, using: provider)
            var batch: ShieldedTransactionBatch?
            var received: [ReceivedNote] = []
            var respent = Set<[UInt8]>()
            var spent = Set<[UInt8]>()
            while let read = try await group.next() {
                switch read {
                case .tagged(let tagged):
                    var known = Set(notes.map(\.nullifier.bigEndianBytes))
                    let delivered = try tagged.transactions.flatMap { try ReceivedNote.notes(in: $0, of: account) }
                        .filter { known.insert($0.nullifier.bigEndianBytes).inserted }
                    received = delivered.filter { !localSpends.contains($0.nullifier.bigEndianBytes) }
                    respent = localSpends.intersection(delivered.map(\.nullifier.bigEndianBytes))
                    spent.formUnion(tagged.transactions.flatMap(\.nullifiers))
                    Self.readSpends(of: received.filter { !spent.contains($0.nullifier.bigEndianBytes) }, into: &group, using: provider)
                    batch = tagged
                case .spends(let transactions):
                    spent.formUnion(transactions.flatMap(\.nullifiers))
                }
            }
            return (batch, received, respent, spent)
        }
        let kept = (notes + received).filter { !spent.contains($0.nullifier.bigEndianBytes) }
            .sorted { ($0.slot, $0.signature, $0.leafIndex, $0.utxo.treeID) < ($1.slot, $1.signature, $1.leafIndex, $1.utxo.treeID) }
        let reported = Set((batch?.transactions.map(\.signature) ?? []) + kept.map(\.signature))
        return try NoteSyncState(
            position: batch?.position ?? position,
            notes: kept,
            outputTreeID: batch?.outputTreeID,
            pending: pending.filter { !reported.contains($0.signature) },
            localSpends: respent.subtracting(spent)
        )
    }

    /// Adds a read of the transactions that spent any of the notes.
    ///
    /// - Parameters:
    ///   - notes: The notes whose spends to read.
    ///   - group: The sync's reads.
    ///   - provider: The indexer.
    private static func readSpends(
        of notes: [ReceivedNote],
        into group: inout ThrowingTaskGroup<SyncRead, any Error>,
        using provider: some PrivateNoteProviding
    ) {
        guard !notes.isEmpty else { return }
        let nullifiers = notes.map(\.nullifier.bigEndianBytes)
        group.addTask { .spends(try await provider.shieldedTransactions(spending: nullifiers)) }
    }
}

/// The result of one of a sync's reads.
private enum SyncRead: Sendable {
    case tagged(ShieldedTransactionBatch)
    case spends([ShieldedTransaction])
}
