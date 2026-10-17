import Foundation
import ModularArithmetic
public import RPC
import Transactions

/// An account's unspent notes, its pending amounts, and where its next read of the indexer resumes.
///
/// A state is a value: a sync returns a new state and leaves the old one unchanged when it throws or
/// is cancelled, so the caller stores a state only after a sync succeeds. The notes are SOL notes in
/// slot, signature, leaf, and tree order; notes of other assets don't decode and are skipped, so a
/// version that receives tokens starts again from ``init()``. After a transaction succeeds, the
/// caller records it: its spent notes leave at once, and the lamports that it gave the account stay
/// pending, counted but not spendable, until the indexer reports the transaction. The total never
/// exceeds a 64-bit integer: a sync or a record that would exceed it throws, and decoding rejects it.
/// Every field is required when decoding. Descriptions and reflection omit the values.
public struct NoteSyncState: Sendable, Equatable, Codable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// A state that can't hold its notes.
    public enum ValidationError: Error, Equatable {
        /// The notes and pending amounts hold more lamports than a 64-bit integer.
        case amountOverflow
    }

    /// The encoded fields of a state.
    private enum CodingKeys: String, CodingKey {
        case position, notes, outputTreeID, pending, localSpends
    }

    /// The length of a nullifier, in bytes.
    private static let nullifierLength = 32

    /// Where the next read of the account's view tags resumes, or `nil` before the first sync.
    let position: NoteSyncPosition?

    /// The unspent notes, in slot, signature, leaf, and tree order. Only these notes can be spent.
    public let notes: [ReceivedNote]

    /// The tree that receives new outputs, as the latest sync's indexer read reported it, or `nil`
    /// before a sync or when the indexer reports none.
    public let outputTreeID: UInt16?

    /// The lamports of recorded transactions that the indexer hasn't reported, in record order.
    let pending: [PendingAmount]

    /// The 32-byte nullifiers of notes that a recorded transaction spent and that a later sync
    /// returned again without reporting the spend; such notes stay hidden.
    let localSpends: Set<[UInt8]>

    /// The total of the unspent notes and the pending amounts, in lamports.
    public var lamports: UInt64 {
        notes.reduce(0) { $0 + $1.lamports } + pendingLamports
    }

    /// The total of the pending amounts, which can't be spent until the indexer reports them, in
    /// lamports.
    public var pendingLamports: UInt64 {
        pending.reduce(0) { $0 + $1.lamports }
    }

    /// A description that omits the values.
    public var description: String { "NoteSyncState" }

    /// A debugging description that omits the values.
    public var debugDescription: String { description }

    /// A reflection view that omits the values.
    public var customMirror: Mirror { Mirror(self, children: [:]) }

    /// Creates the state of an account that hasn't synced: no position, notes, output tree, or
    /// pending amounts.
    public init() {
        position = nil
        notes = []
        outputTreeID = nil
        pending = []
        localSpends = []
    }

    /// Creates a state whose notes and pending amounts total at most a 64-bit integer.
    ///
    /// - Parameters:
    ///   - position: The position where the next read resumes.
    ///   - notes: The unspent notes.
    ///   - outputTreeID: The tree that receives new outputs, if known.
    ///   - pending: The pending amounts.
    ///   - localSpends: The nullifiers of recorded spends to keep hiding.
    /// - Throws: ``ValidationError/amountOverflow`` if the notes and pending amounts hold more
    ///   lamports than a 64-bit integer.
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

    /// Decodes a state and checks its nullifiers and that its total fits a 64-bit integer.
    ///
    /// - Parameter decoder: The decoder that supplies the state's fields.
    /// - Throws: A decoding error for a missing or invalid field, a nullifier that isn't 32 bytes, or
    ///   notes and pending amounts that hold more lamports than a 64-bit integer.
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

    /// Encodes the state's fields, with an absent output tree as `null` and the nullifiers in byte
    /// order.
    ///
    /// - Parameter encoder: The encoder that receives the state's fields.
    /// - Throws: An encoding error if a field can't be written.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(position, forKey: .position)
        try container.encode(notes, forKey: .notes)
        try container.encode(outputTreeID, forKey: .outputTreeID)
        try container.encode(pending, forKey: .pending)
        try container.encode(localSpends.sorted { $0.lexicographicallyPrecedes($1) }.map { Data($0) }, forKey: .localSpends)
    }

    /// Records a spend's successful transaction: its notes leave at once, and the lamports that it
    /// gave the account stay pending until the indexer reports the transaction.
    ///
    /// A later sync keeps hiding the spent notes if the indexer returns them again before it reports
    /// their spend. Nothing becomes pending if a sync already returned the transaction's notes, if
    /// none of the spent notes is still held, since a nullifier is published once and a sync already
    /// saw the transaction, or if the transaction is already recorded.
    ///
    /// - Parameters:
    ///   - spend: The spend whose transaction succeeded.
    ///   - signature: The transaction's signature.
    /// - Returns: The state without the spent notes, with the spend's ``PrivateSpend/receivedLamports``
    ///   pending when positive and not yet counted.
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

    /// Records a deposit's successful transaction to the account: its lamports stay pending until
    /// the indexer reports the transaction.
    ///
    /// Nothing becomes pending if a sync already returned the deposit's note or the deposit is
    /// already recorded. A deposit recorded after another device's sync already saw and spent its
    /// note stays pending until a sync from the start.
    ///
    /// - Parameters:
    ///   - lamports: The deposited amount.
    ///   - signature: The transaction's signature.
    /// - Returns: The state with the deposit pending, unless it's already counted.
    /// - Throws: ``Transactions/ValidationError/invalidAmount`` for zero lamports, or
    ///   ``ValidationError/amountOverflow`` if the total would exceed a 64-bit integer.
    public func recording(depositOf lamports: UInt64, signature: String) throws -> NoteSyncState {
        guard lamports > 0 else { throw Transactions.ValidationError.invalidAmount }
        return try NoteSyncState(
            position: position, notes: notes, outputTreeID: outputTreeID, pending: pending(adding: lamports, signature: signature),
            localSpends: localSpends
        )
    }

    /// Returns the pending amounts with a recorded transaction's lamports, unless they're zero or
    /// already counted: as a note that a sync returned, or as a pending amount.
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
    /// Two reads start at once: the transactions tagged with the account's view tags after
    /// ``position``, and the transactions that spent the current notes. The view tags are the
    /// signing address and the x-coordinate of the viewing public key. As soon as the tagged batch
    /// arrives, a third read starts for the spends of its new notes that no returned transaction
    /// spends yet, while the second read may still run. A spend read without notes isn't sent, and the
    /// first error cancels the other reads. A note is new if its nullifier is new, and spent if any
    /// transaction that a read returns publishes its nullifier.
    ///
    /// New notes that a recorded spend consumed stay hidden. A recorded spend stops being tracked
    /// once a returned transaction publishes its nullifier or the batch doesn't return its note. A
    /// pending amount ends when the batch returns its transaction or a kept note comes from it, since
    /// its notes then count instead.
    ///
    /// - Parameters:
    ///   - account: The account whose notes to sync, the account of this state.
    ///   - provider: The indexer of the account's network.
    /// - Returns: The state at the batch's position, with the current and new notes that aren't spent
    ///   and the batch's output tree.
    /// - Throws: ``ValidationError/amountOverflow`` if the unspent notes and pending amounts hold more
    ///   lamports than a 64-bit integer, a ``RPC/PrivateNoteError`` if the position came from other
    ///   view tags, a cipher or key agreement error from opening a note, or a request, transport,
    ///   response, or cancellation error.
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

    /// Adds a read of the transactions that spent any of the notes, without a read when there are none.
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
    /// The transactions tagged with the account's view tags, and the next position.
    case tagged(ShieldedTransactionBatch)
    /// The transactions that spent some of the notes.
    case spends([ShieldedTransaction])
}
