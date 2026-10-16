import ModularArithmetic
public import RPC
import Transactions

/// An account's unspent notes and where its next read of the indexer resumes.
///
/// A state is a value: a sync returns a new state and leaves the old one unchanged when it throws or
/// is cancelled, so the caller stores a state only after a sync succeeds. The notes are SOL notes in
/// slot, signature, leaf, and tree order; notes of other assets don't decode and are skipped, so a
/// version that receives tokens starts again from ``init()``. The notes' total never exceeds a
/// 64-bit integer: a sync that would exceed it throws, and decoding rejects it. Descriptions and
/// reflection omit the values.
public struct NoteSyncState: Sendable, Equatable, Codable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// A state that can't hold its notes.
    public enum ValidationError: Error, Equatable {
        /// The notes hold more lamports than a 64-bit integer.
        case amountOverflow
    }

    /// The encoded fields of a state.
    private enum CodingKeys: String, CodingKey {
        case position, notes
    }

    /// Where the next read of the account's view tag resumes, or `nil` before the first sync.
    let position: NoteSyncPosition?

    /// The unspent notes, in slot, signature, leaf, and tree order.
    public let notes: [ReceivedNote]

    /// The total of the unspent notes, in lamports.
    public var lamports: UInt64 {
        notes.reduce(0) { $0 + $1.lamports }
    }

    /// A description that omits the values.
    public var description: String { "NoteSyncState" }

    /// A debugging description that omits the values.
    public var debugDescription: String { description }

    /// A reflection view that omits the values.
    public var customMirror: Mirror { Mirror(self, children: [:]) }

    /// Creates the state of an account that hasn't synced: no position and no notes.
    public init() {
        position = nil
        notes = []
    }

    /// Creates a state from a position and notes whose total fits a 64-bit integer.
    ///
    /// - Parameters:
    ///   - position: The position where the next read resumes.
    ///   - notes: The unspent notes.
    /// - Throws: ``ValidationError/amountOverflow`` if the notes hold more lamports than a 64-bit
    ///   integer.
    init(position: NoteSyncPosition?, notes: [ReceivedNote]) throws {
        _ = try notes.reduce(UInt64(0)) { total, note in
            let (sum, overflow) = total.addingReportingOverflow(note.lamports)
            guard !overflow else { throw ValidationError.amountOverflow }
            return sum
        }
        self.position = position
        self.notes = notes
    }

    /// Decodes a state and checks that its notes' total fits a 64-bit integer.
    ///
    /// - Parameter decoder: The decoder that supplies the state's fields.
    /// - Throws: A decoding error for a missing or invalid field, or for notes that hold more lamports
    ///   than a 64-bit integer.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let position = try container.decodeIfPresent(NoteSyncPosition.self, forKey: .position)
        let notes = try container.decode([ReceivedNote].self, forKey: .notes)
        do {
            try self.init(position: position, notes: notes)
        } catch {
            throw DecodingError.dataCorruptedError(forKey: .notes, in: container, debugDescription: "The notes' total overflows.")
        }
    }

    /// Reads the indexer for the account's new notes and spends and returns the next state.
    ///
    /// Two reads start at once: the transactions tagged with the account's signing address after
    /// ``position``, and the transactions that spent the current notes. As soon as the tagged batch
    /// arrives, a third read starts for the spends of its new notes that no returned transaction
    /// spends yet, while the second read may still run. A spend read without notes isn't sent, and the
    /// first error cancels the other reads. A note is new if its nullifier is new, and spent if any
    /// transaction that a read returns publishes its nullifier.
    ///
    /// - Parameters:
    ///   - account: The account whose notes to sync, the account of this state.
    ///   - provider: The indexer of the account's network.
    /// - Returns: The state at the batch's position, with the current and new notes that aren't spent.
    /// - Throws: ``ValidationError/amountOverflow`` if the unspent notes hold more lamports than a
    ///   64-bit integer, a ``RPC/PrivateNoteError`` if the position came from other view tags, a cipher
    ///   or key agreement error from opening a note, or a request, transport, response, or
    ///   cancellation error.
    @concurrent
    public func synced(for account: ShieldedAccount, using provider: some PrivateNoteProviding) async throws -> NoteSyncState {
        let (position, notes) = (position, notes)
        let (nextPosition, received, spent) = try await withThrowingTaskGroup(of: SyncRead.self) { group in
            group.addTask {
                .tagged(try await provider.shieldedTransactions(taggedWith: [account.signingAddress.bytes], after: position))
            }
            Self.readSpends(of: notes, into: &group, using: provider)
            var nextPosition = position
            var received: [ReceivedNote] = []
            var spent = Set<[UInt8]>()
            while let read = try await group.next() {
                switch read {
                case .tagged(let batch):
                    var known = Set(notes.map(\.nullifier.bigEndianBytes))
                    received = try batch.transactions.flatMap { try ReceivedNote.notes(in: $0, of: account) }
                        .filter { known.insert($0.nullifier.bigEndianBytes).inserted }
                    spent.formUnion(batch.transactions.flatMap(\.nullifiers))
                    Self.readSpends(of: received.filter { !spent.contains($0.nullifier.bigEndianBytes) }, into: &group, using: provider)
                    nextPosition = batch.position
                case .spends(let transactions):
                    spent.formUnion(transactions.flatMap(\.nullifiers))
                }
            }
            return (nextPosition, received, spent)
        }
        return try NoteSyncState(
            position: nextPosition,
            notes: (notes + received).filter { !spent.contains($0.nullifier.bigEndianBytes) }
                .sorted { ($0.slot, $0.signature, $0.leafIndex, $0.utxo.treeID) < ($1.slot, $1.signature, $1.leafIndex, $1.utxo.treeID) }
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
    /// The transactions tagged with the account's signing address, and the next position.
    case tagged(ShieldedTransactionBatch)
    /// The transactions that spent some of the notes.
    case spends([ShieldedTransaction])
}
