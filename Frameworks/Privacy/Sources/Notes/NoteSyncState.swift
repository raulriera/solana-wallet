import Foundation
import ModularArithmetic
public import RPC
import Transactions

/// An account's unspent notes, the received notes it hasn't confirmed yet, its pending amounts, and where its next read
/// of the indexer resumes.
public struct NoteSyncState: Sendable, Equatable, Codable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// An error in a state's amounts.
    public enum ValidationError: Error, Equatable {
        /// The notes and pending amounts total more lamports than a 64-bit integer holds.
        case amountOverflow
    }

    /// The keys of a state's encoded fields.
    private enum CodingKeys: String, CodingKey {
        case position, notes, unconfirmedNotes, outputTreeID, pending, localSpends, rejectedSpends, missingSpendReads
    }

    /// The length of a nullifier, in bytes.
    private static let nullifierLength = 32

    /// The most batches that a sync to the end reads.
    private static let maximumBatchCount = 128

    /// The most transactions that a sync reads to confirm claimed spends of counted notes.
    private static let maximumSpendReads = 8

    /// The number of reads in a row that find no transaction for a claimed spend before the claim counts as refuted.
    private static let maximumMissingReads = 10

    /// Where the next read resumes, or `nil` before the first sync.
    let position: NoteSyncPosition?

    /// The unspent notes whose Merkle proofs lead to roots that their trees' accounts hold, in slot, signature, leaf,
    /// and tree order.
    public let notes: [ReceivedNote]

    /// The unspent received notes whose roots their trees' accounts didn't hold yet, which the next sync checks again
    /// and no amount counts, in slot, signature, leaf, and tree order.
    let unconfirmedNotes: [ReceivedNote]

    /// The ID of the tree that receives new outputs, or `nil` if no sync reported one.
    public let outputTreeID: UInt16?

    let pending: [PendingAmount]

    /// The nullifiers of recorded spends whose notes a sync returned before it reported the spend.
    let localSpends: Set<[UInt8]>

    /// The signatures of claimed spends of counted notes whose finalized transactions failed or don't spend the
    /// claimed nullifiers, or whose transactions ten reads in a row didn't find, while a claim still names them.
    let rejectedSpends: Set<String>

    /// The number of reads in a row that found no transaction for each claimed spend of counted notes, by signature,
    /// while a claim still names it.
    let missingSpendReads: [String: Int]

    public var pendingLamports: UInt64 {
        pending.reduce(0) { $0 + $1.lamports }
    }

    /// The total of the unspent notes, which a spend can use, in lamports.
    public var spendableLamports: UInt64 {
        notes.reduce(0) { $0 + $1.lamports }
    }

    /// Whether the state holds received notes whose roots their trees' accounts didn't hold yet, which no amount
    /// counts.
    public var hasUnconfirmedNotes: Bool {
        !unconfirmedNotes.isEmpty
    }

    public var description: String { "NoteSyncState" }

    public var debugDescription: String { description }

    public var customMirror: Mirror { Mirror(self, children: [:]) }

    /// Creates the state of an account that hasn't synced.
    public init() {
        position = nil
        notes = []
        unconfirmedNotes = []
        outputTreeID = nil
        pending = []
        localSpends = []
        rejectedSpends = []
        missingSpendReads = [:]
    }

    /// Creates a state and checks that its total fits a 64-bit integer.
    ///
    /// - Parameters:
    ///   - position: Where the next read resumes.
    ///   - notes: The unspent notes.
    ///   - unconfirmedNotes: The unspent received notes that a sync hasn't confirmed yet.
    ///   - outputTreeID: The ID of the tree that receives new outputs, if known.
    ///   - pending: The pending amounts.
    ///   - localSpends: The nullifiers of recorded spends to keep hiding.
    ///   - rejectedSpends: The signatures of claimed spends that count as refuted.
    ///   - missingSpendReads: The number of reads in a row that found no transaction for each claimed spend.
    /// - Throws: ``ValidationError/amountOverflow`` if the total exceeds a 64-bit integer.
    init(
        position: NoteSyncPosition?,
        notes: [ReceivedNote],
        unconfirmedNotes: [ReceivedNote],
        outputTreeID: UInt16?,
        pending: [PendingAmount],
        localSpends: Set<[UInt8]>,
        rejectedSpends: Set<String>,
        missingSpendReads: [String: Int]
    ) throws {
        _ = try (notes.map(\.lamports) + pending.map(\.lamports)).reduce(UInt64(0)) { total, lamports in
            let (sum, overflow) = total.addingReportingOverflow(lamports)
            guard !overflow else { throw ValidationError.amountOverflow }
            return sum
        }
        self.position = position
        self.notes = notes
        self.unconfirmedNotes = unconfirmedNotes
        self.outputTreeID = outputTreeID
        self.pending = pending
        self.localSpends = localSpends
        self.rejectedSpends = rejectedSpends
        self.missingSpendReads = missingSpendReads
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let position = try container.decodeIfPresent(NoteSyncPosition.self, forKey: .position)
        let notes = try container.decode([ReceivedNote].self, forKey: .notes)
        let unconfirmedNotes = try container.decode([ReceivedNote].self, forKey: .unconfirmedNotes)
        let outputTreeID = try container.decode(UInt16?.self, forKey: .outputTreeID)
        let pending = try container.decode([PendingAmount].self, forKey: .pending)
        let localSpends = try container.decode([Data].self, forKey: .localSpends).map { [UInt8]($0) }
        guard localSpends.allSatisfy({ $0.count == Self.nullifierLength }) else {
            throw DecodingError.dataCorruptedError(forKey: .localSpends, in: container, debugDescription: "A nullifier has 32 bytes.")
        }
        let rejectedSpends = try container.decode([String].self, forKey: .rejectedSpends)
        let missingSpendReads = try container.decode([String: Int].self, forKey: .missingSpendReads)
        do {
            try self.init(
                position: position, notes: notes, unconfirmedNotes: unconfirmedNotes, outputTreeID: outputTreeID, pending: pending,
                localSpends: Set(localSpends), rejectedSpends: Set(rejectedSpends), missingSpendReads: missingSpendReads
            )
        } catch {
            throw DecodingError.dataCorruptedError(forKey: .notes, in: container, debugDescription: "The total overflows.")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(position, forKey: .position)
        try container.encode(notes, forKey: .notes)
        try container.encode(unconfirmedNotes, forKey: .unconfirmedNotes)
        try container.encode(outputTreeID, forKey: .outputTreeID)
        try container.encode(pending, forKey: .pending)
        try container.encode(localSpends.sorted { $0.lexicographicallyPrecedes($1) }.map { Data($0) }, forKey: .localSpends)
        try container.encode(rejectedSpends.sorted(), forKey: .rejectedSpends)
        try container.encode(missingSpendReads, forKey: .missingSpendReads)
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
            position: position, notes: notes.filter { !spent.contains($0.nullifier.bigEndianBytes) },
            unconfirmedNotes: unconfirmedNotes, outputTreeID: outputTreeID,
            pending: isHeld ? pending(adding: spend.receivedLamports, signature: signature) : pending,
            localSpends: localSpends.union(spent), rejectedSpends: rejectedSpends, missingSpendReads: missingSpendReads
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
            position: position, notes: notes, unconfirmedNotes: unconfirmedNotes, outputTreeID: outputTreeID,
            pending: pending(adding: lamports, signature: signature), localSpends: localSpends, rejectedSpends: rejectedSpends,
            missingSpendReads: missingSpendReads
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

    /// Reads one batch of the account's new notes and spends from the indexer, checks the received notes against their
    /// trees' on-chain roots and up to eight claimed spends of counted notes against their finalized transactions, and
    /// returns the next state.
    ///
    /// - Parameters:
    ///   - account: The account of this state.
    ///   - rpc: The client of the account's network, which reads the trees' accounts and the claimed spends'
    ///     transactions.
    ///   - indexer: The indexer of the account's network, which reads the notes, their spends, and their Merkle proofs.
    /// - Returns: The state with the unspent notes, the notes whose roots aren't on chain yet, and the position of the
    ///   next read.
    /// - Throws: ``ValidationError/amountOverflow`` if the total exceeds a 64-bit integer, a
    ///   ``RPC/PrivateNoteError`` if the position came from other view tags,
    ///   ``RPC/RPCError/InvalidResponse/mismatchedProofs`` if the indexer doesn't return one proof per note, a
    ///   ``ShieldedPool/TreeError`` if a tree's account isn't valid, a ``Transactions/ValidationError`` if a tree's
    ///   derivation fails, ``ShieldedPool/InstructionError/unknownLayout`` if a claimed spend's successful
    ///   transaction holds a spend instruction of an unknown layout, a cipher or key agreement error, or a request,
    ///   transport, response, or cancellation error.
    @concurrent
    public func synced(
        for account: ShieldedAccount,
        rpc: some RPC,
        indexer: some PrivateNoteProviding
    ) async throws -> NoteSyncState {
        var reads = SpendReads()
        return try await syncedBatch(for: account, rpc: rpc, indexer: indexer, reads: &reads).state
    }

    /// Reads batches of the account's new notes and spends from the indexer until no more come, checking the received
    /// notes against their trees' on-chain roots and up to eight claimed spends of counted notes against their
    /// finalized transactions, and returns the final state.
    ///
    /// - Parameters:
    ///   - account: The account of this state.
    ///   - rpc: The client of the account's network, which reads the trees' accounts and the claimed spends'
    ///     transactions.
    ///   - indexer: The indexer of the account's network, which reads the notes, their spends, and their Merkle proofs.
    /// - Returns: The state with the unspent notes, the notes whose roots aren't on chain yet, and the position of the
    ///   next read.
    /// - Throws: An error as ``synced(for:rpc:indexer:)`` describes, or
    ///   ``RPC/RPCError/InvalidResponse/endlessStream`` if more come after 128 batches.
    @concurrent
    public func syncedToEnd(
        for account: ShieldedAccount,
        rpc: some RPC,
        indexer: some PrivateNoteProviding
    ) async throws -> NoteSyncState {
        var state = self
        var reads = SpendReads()
        for _ in 0..<Self.maximumBatchCount {
            try Task.checkCancellation()
            let (next, moreComing) = try await state.syncedBatch(for: account, rpc: rpc, indexer: indexer, reads: &reads)
            guard moreComing else { return next }
            state = next
        }
        throw RPCError.invalidResponse(.endlessStream)
    }

    /// Reads one batch of the account's new notes and spends from the indexer, checks the received notes against
    /// their trees' on-chain roots, and confirms claimed spends of counted notes with their transactions.
    ///
    /// - Parameters:
    ///   - account: The account of this state.
    ///   - rpc: The client of the account's network.
    ///   - indexer: The indexer of the account's network.
    ///   - reads: The claimed spends that the sync already read, which this adds to.
    /// - Returns: The next state, and whether the indexer holds more after its position.
    /// - Throws: An error as ``synced(for:rpc:indexer:)`` describes.
    private func syncedBatch(
        for account: ShieldedAccount,
        rpc: some RPC,
        indexer: some PrivateNoteProviding,
        reads: inout SpendReads
    ) async throws -> (state: NoteSyncState, moreComing: Bool) {
        let (position, notes, unconfirmedNotes, localSpends, tags) = (position, notes, unconfirmedNotes, localSpends, account.viewTags)
        let held = notes + unconfirmedNotes
        let (batch, delivered, checked, respent, claims) = try await withThrowingTaskGroup(of: SyncRead.self) { group in
            group.addTask {
                .tagged(try await indexer.shieldedTransactions(taggedWith: tags, after: position))
            }
            Self.readSpends(of: held, into: &group, using: indexer)
            var batch: ShieldedTransactionBatch?
            var delivered: [ReceivedNote] = []
            var checked: [(note: ReceivedNote, status: ReceivedNote.InclusionStatus)] = []
            var respent = Set<[UInt8]>()
            var claims: [ShieldedTransaction] = []
            while let read = try await group.next() {
                switch read {
                case .tagged(let tagged):
                    var known = Set(held.map(\.nullifier.bigEndianBytes))
                    delivered = try tagged.transactions.flatMap { try ReceivedNote.notes(in: $0, of: account) }
                        .filter { known.insert($0.nullifier.bigEndianBytes).inserted }
                    respent = localSpends.intersection(delivered.map(\.nullifier.bigEndianBytes))
                    claims += tagged.transactions
                    let claimed = Set(claims.flatMap(\.nullifiers))
                    let received = delivered.filter {
                        !localSpends.contains($0.nullifier.bigEndianBytes) && !claimed.contains($0.nullifier.bigEndianBytes)
                    }
                    Self.readSpends(of: received, into: &group, using: indexer)
                    Self.checkInclusion(of: unconfirmedNotes + received, into: &group, rpc: rpc, indexer: indexer)
                    batch = tagged
                case .spends(let transactions):
                    claims += transactions
                case .inclusion(let statuses):
                    checked = statuses
                }
            }
            return (batch, delivered, checked, respent, claims)
        }
        let uncounted = Set((unconfirmedNotes + delivered).map(\.nullifier.bigEndianBytes))
        let counted = SpendClaim.claims(in: claims, of: Set(notes.map(\.nullifier.bigEndianBytes)))
        let claimed = Set(counted.map(\.signature))
        let named = rejectedSpends.intersection(claimed)
        let unread = counted.unread(by: reads, skipping: named, limit: Self.maximumSpendReads)
        let (proven, refuted, missing) = try await Self.confirm(unread, recording: &reads, using: rpc)
        let (missingReads, expired) = missingReads(adding: missing, read: Set(unread.map(\.signature)), claimed: claimed)
        let spent = proven.union(uncounted.intersection(claims.flatMap(\.nullifiers)))
        let confirmed = notes + checked.filter { $0.status == .included }.map(\.note)
        let seen = held + delivered
        let waiting = Set(seen.filter { !spent.contains($0.nullifier.bigEndianBytes) }.map(\.signature))
        let settled = Set(confirmed.map(\.signature)).union(Set(seen.map(\.signature)).subtracting(waiting))
        let state = try NoteSyncState(
            position: batch?.position ?? position,
            notes: Self.unspent(confirmed, excluding: spent),
            unconfirmedNotes: Self.unspent(checked.filter { $0.status == .unconfirmed }.map(\.note), excluding: spent),
            outputTreeID: batch?.outputTreeID,
            pending: pending.filter { !settled.contains($0.signature) },
            localSpends: respent.subtracting(spent),
            rejectedSpends: named.union(refuted).union(expired),
            missingSpendReads: missingReads
        )
        return (state, batch?.moreComing ?? false)
    }

    /// Counts the reads in a row that found no transaction for each claimed spend that a claim still names.
    ///
    /// - Parameters:
    ///   - missing: The signatures of the read claims whose transactions the client didn't find.
    ///   - read: The signatures of the claims that the batch read.
    ///   - claimed: The signatures of the claims of counted notes.
    /// - Returns: The counts below the limit by signature, and the signatures whose count reached it.
    private func missingReads(adding missing: Set<String>, read: Set<String>, claimed: Set<String>)
        -> (counts: [String: Int], expired: Set<String>) {
        var counts = missingSpendReads.filter { claimed.contains($0.key) && !read.contains($0.key) }
        for signature in missing { counts[signature] = missingSpendReads[signature, default: 0] + 1 }
        let expired = Set(counts.filter { $0.value >= Self.maximumMissingReads }.keys)
        return (counts.filter { !expired.contains($0.key) }, expired)
    }

    /// Reads the transactions of claimed spends at once.
    ///
    /// - Parameters:
    ///   - claims: The claims to read.
    ///   - reads: The claimed spends that the sync read, which this adds to.
    ///   - rpc: The client that reads the transactions at finalized commitment.
    /// - Returns: The nullifiers that the transactions spent, the signatures of the finalized transactions that
    ///   failed or don't spend every nullifier that their claim names, and the signatures whose transactions the
    ///   client didn't find.
    /// - Throws: ``ShieldedPool/InstructionError/unknownLayout`` if a successful transaction holds a spend instruction
    ///   of an unknown layout, or a request, transport, response, or cancellation error.
    private static func confirm(
        _ claims: [SpendClaim],
        recording reads: inout SpendReads,
        using rpc: some RPC
    ) async throws -> (proven: Set<[UInt8]>, refuted: Set<String>, missing: Set<String>) {
        reads.record(claims)
        return try await withThrowingTaskGroup(of: (claim: SpendClaim, spent: Set<[UInt8]>?).self) { group in
            for claim in claims {
                group.addTask {
                    guard let transaction = try await rpc.send(GetTransaction(signature: claim.signature)) else { return (claim, nil) }
                    return (claim, transaction.error == nil ? try ShieldedPool.nullifiers(spentBy: transaction) : [])
                }
            }
            var proven = Set<[UInt8]>()
            var refuted = Set<String>()
            var missing = Set<String>()
            for try await (claim, spent) in group {
                guard let spent else {
                    missing.insert(claim.signature)
                    continue
                }
                proven.formUnion(spent)
                if !claim.nullifiers.isSubset(of: spent) { refuted.insert(claim.signature) }
            }
            return (proven, refuted, missing)
        }
    }

    /// Returns the notes that no nullifier spent, in slot, signature, leaf, and tree order.
    ///
    /// - Parameters:
    ///   - notes: The notes.
    ///   - spent: The spent nullifiers.
    /// - Returns: The unspent notes, in order.
    private static func unspent(_ notes: [ReceivedNote], excluding spent: Set<[UInt8]>) -> [ReceivedNote] {
        notes.filter { !spent.contains($0.nullifier.bigEndianBytes) }
            .sorted { ($0.slot, $0.signature, $0.leafIndex, $0.utxo.treeID) < ($1.slot, $1.signature, $1.leafIndex, $1.utxo.treeID) }
    }

    /// Adds a read of the transactions that spent any of the notes.
    ///
    /// - Parameters:
    ///   - notes: The notes whose spends to read.
    ///   - group: The sync's reads.
    ///   - indexer: The indexer.
    private static func readSpends(
        of notes: [ReceivedNote],
        into group: inout ThrowingTaskGroup<SyncRead, any Error>,
        using indexer: some PrivateNoteProviding
    ) {
        guard !notes.isEmpty else { return }
        let nullifiers = notes.map(\.nullifier.bigEndianBytes)
        group.addTask { .spends(try await indexer.shieldedTransactions(spending: nullifiers)) }
    }

    /// Adds a check of the notes against their trees' on-chain roots.
    ///
    /// - Parameters:
    ///   - notes: The notes to check.
    ///   - group: The sync's reads.
    ///   - rpc: The client that reads the trees' accounts.
    ///   - indexer: The indexer that reads the notes' Merkle proofs.
    private static func checkInclusion(
        of notes: [ReceivedNote],
        into group: inout ThrowingTaskGroup<SyncRead, any Error>,
        rpc: some RPC,
        indexer: some PrivateNoteProviding
    ) {
        guard !notes.isEmpty else { return }
        group.addTask {
            let statuses = try await ReceivedNote.inclusionStatuses(of: notes, rpc: rpc, indexer: indexer)
            return .inclusion(zip(notes, statuses).map { (note: $0, status: $1) })
        }
    }
}

/// The result of one of a sync's reads.
private enum SyncRead: Sendable {
    case tagged(ShieldedTransactionBatch)
    case spends([ShieldedTransaction])
    case inclusion([(note: ReceivedNote, status: ReceivedNote.InclusionStatus)])
}

/// An indexer's claim that a transaction spent counted notes.
private struct SpendClaim: Sendable {
    let signature: String
    let slot: UInt64
    /// The counted notes' nullifiers that the claim names.
    let nullifiers: Set<[UInt8]>

    /// Collects the claims that name counted notes, one per transaction.
    ///
    /// - Parameters:
    ///   - transactions: The indexer's transactions, with the nullifiers that each claims to spend.
    ///   - counted: The nullifiers of the counted notes.
    /// - Returns: One claim per signature that names a counted note, with every counted nullifier that the
    ///   transactions with that signature name, oldest first.
    static func claims(in transactions: [ShieldedTransaction], of counted: Set<[UInt8]>) -> [SpendClaim] {
        let named = Dictionary(grouping: transactions.filter { !counted.isDisjoint(with: $0.nullifiers) }, by: \.signature)
        return named.map { signature, transactions in
            SpendClaim(
                signature: signature, slot: transactions.map(\.slot).min() ?? 0,
                nullifiers: counted.intersection(transactions.flatMap(\.nullifiers))
            )
        }.sorted { ($0.slot, $0.signature) < ($1.slot, $1.signature) }
    }
}

extension [SpendClaim] {
    /// Chooses the claims to read: for each nullifier that the sync hasn't read a claim of, its oldest claim that isn't
    /// skipped, oldest first, until the sync has read a number of claims.
    ///
    /// - Parameters:
    ///   - reads: The claimed spends that the sync already read.
    ///   - skipped: The signatures of claims not to read.
    ///   - limit: The most claims that one sync reads.
    /// - Returns: The claims to read, oldest first.
    fileprivate func unread(by reads: SpendReads, skipping skipped: Set<String>, limit: Int) -> [SpendClaim] {
        var covered = reads.nullifiers
        var chosen: [SpendClaim] = []
        for claim in self where reads.signatures.count + chosen.count < limit {
            guard !skipped.contains(claim.signature), !reads.signatures.contains(claim.signature),
                  !claim.nullifiers.isSubset(of: covered) else { continue }
            chosen.append(claim)
            covered.formUnion(claim.nullifiers)
        }
        return chosen
    }
}

/// The claimed spends that one sync read, across the batches of a sync to the end.
private struct SpendReads {
    /// The signatures of the transactions that the sync read.
    private(set) var signatures: Set<String> = []
    /// The nullifiers whose claims the sync read.
    private(set) var nullifiers: Set<[UInt8]> = []

    /// Adds claims that the sync reads.
    ///
    /// - Parameter claims: The claims.
    mutating func record(_ claims: [SpendClaim]) {
        signatures.formUnion(claims.map(\.signature))
        nullifiers.formUnion(claims.flatMap(\.nullifiers))
    }
}
