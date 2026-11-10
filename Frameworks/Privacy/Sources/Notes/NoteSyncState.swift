import Foundation
import ModularArithmetic
public import RPC
import Transactions

/// An account's unspent notes, the received notes it hasn't confirmed yet, its pending amounts, and where its next read
/// of the indexer resumes.
public struct NoteSyncState: Sendable, Equatable, Codable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// An error in a state's amounts.
    public enum ValidationError: Error, Equatable {
        /// The notes and pending amounts of one asset total more than a 64-bit integer holds.
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

    /// The SOL that recorded transactions gave the account and no note counts yet, in lamports.
    public var pendingLamports: UInt64 {
        pendingAmount(of: .sol)
    }

    /// The total of the unspent SOL notes, which a spend can use, in lamports.
    public var spendableLamports: UInt64 {
        spendableAmount(of: .sol)
    }

    /// Returns the total of a token's unspent notes.
    ///
    /// - Parameter token: The token.
    /// - Returns: The total, in the token's smallest unit.
    public func spendableAmount(of token: PrivateToken) -> UInt64 {
        spendableAmount(of: token.asset)
    }

    /// Returns the amount of a token that recorded transactions gave the account and no note counts yet.
    ///
    /// - Parameter token: The token.
    /// - Returns: The amount, in the token's smallest unit.
    public func pendingAmount(of token: PrivateToken) -> UInt64 {
        pendingAmount(of: token.asset)
    }

    /// Returns the total of an asset's unspent notes.
    ///
    /// - Parameter asset: The asset.
    /// - Returns: The total, in the asset's smallest unit.
    private func spendableAmount(of asset: ConfidentialPlaintext.Asset) -> UInt64 {
        notes(of: asset).reduce(0) { $0 + $1.amount }
    }

    /// Returns the amount of an asset that recorded transactions gave the account and no note counts yet.
    ///
    /// - Parameter asset: The asset.
    /// - Returns: The amount, in the asset's smallest unit.
    private func pendingAmount(of asset: ConfidentialPlaintext.Asset) -> UInt64 {
        pending.filter { $0.asset == asset }.reduce(0) { $0 + $1.amount }
    }

    /// Returns the unspent notes of an asset.
    ///
    /// - Parameter asset: The asset.
    /// - Returns: The asset's notes, in slot, signature, leaf, and tree order.
    func notes(of asset: ConfidentialPlaintext.Asset) -> [ReceivedNote] {
        notes.filter { $0.utxo.mint == asset.mint }
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
    /// - Throws: ``ValidationError/amountOverflow`` if an asset's total exceeds a 64-bit integer.
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
        let amounts = notes.map { ($0.utxo.mint, $0.amount) } + pending.map { ($0.asset.mint, $0.amount) }
        _ = try Dictionary(amounts) { total, amount in
            let (sum, overflow) = total.addingReportingOverflow(amount)
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
            pending: isHeld ? pending(adding: spend.receivedAmount, of: spend.asset, signature: signature) : pending,
            localSpends: localSpends.union(spent), rejectedSpends: rejectedSpends, missingSpendReads: missingSpendReads
        )
    }

    /// Records a SOL deposit's successful transaction to the account.
    ///
    /// - Parameters:
    ///   - lamports: The deposited amount.
    ///   - signature: The transaction's signature.
    /// - Returns: The state with the deposit pending.
    /// - Throws: ``Transactions/ValidationError/invalidAmount`` for zero lamports, or
    ///   ``ValidationError/amountOverflow`` if SOL's total would exceed a 64-bit integer.
    public func recording(depositOf lamports: UInt64, signature: String) throws -> NoteSyncState {
        try recording(depositOf: lamports, of: .sol, signature: signature)
    }

    /// Records a token deposit's successful transaction to the account.
    ///
    /// - Parameters:
    ///   - amount: The deposited amount, in the token's smallest unit.
    ///   - token: The deposited token.
    ///   - signature: The transaction's signature.
    /// - Returns: The state with the deposit pending.
    /// - Throws: ``Transactions/ValidationError/invalidAmount`` for a zero amount, or
    ///   ``ValidationError/amountOverflow`` if the token's total would exceed a 64-bit integer.
    public func recording(depositOf amount: UInt64, of token: PrivateToken, signature: String) throws -> NoteSyncState {
        try recording(depositOf: amount, of: token.asset, signature: signature)
    }

    /// Records a deposit's successful transaction to the account.
    ///
    /// - Parameters:
    ///   - amount: The deposited amount, in the asset's smallest unit.
    ///   - asset: The deposited asset.
    ///   - signature: The transaction's signature.
    /// - Returns: The state with the deposit pending.
    /// - Throws: ``Transactions/ValidationError/invalidAmount`` for a zero amount, or
    ///   ``ValidationError/amountOverflow`` if the asset's total would exceed a 64-bit integer.
    private func recording(
        depositOf amount: UInt64, of asset: ConfidentialPlaintext.Asset, signature: String
    ) throws -> NoteSyncState {
        guard amount > 0 else { throw Transactions.ValidationError.invalidAmount }
        return try NoteSyncState(
            position: position, notes: notes, unconfirmedNotes: unconfirmedNotes, outputTreeID: outputTreeID,
            pending: pending(adding: amount, of: asset, signature: signature), localSpends: localSpends,
            rejectedSpends: rejectedSpends, missingSpendReads: missingSpendReads
        )
    }

    /// Adds a recorded transaction's amount to the pending amounts unless it's zero or already counted.
    ///
    /// - Parameters:
    ///   - amount: The amount that the transaction gave the account, in the asset's smallest unit.
    ///   - asset: The asset of the amount.
    ///   - signature: The transaction's signature.
    /// - Returns: The pending amounts.
    private func pending(adding amount: UInt64, of asset: ConfidentialPlaintext.Asset, signature: String) -> [PendingAmount] {
        let isCounted = notes.contains { $0.signature == signature } || pending.contains { $0.signature == signature }
        return amount == 0 || isCounted
            ? pending : pending + [PendingAmount(signature: signature, asset: asset, amount: amount)]
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
        let (proven, rejected, missingReads) = try await confirmedSpends(in: claims, reads: &reads, using: rpc)
        let uncounted = Set((unconfirmedNotes + delivered).map(\.nullifier.bigEndianBytes))
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
            rejectedSpends: rejected,
            missingSpendReads: missingReads
        )
        return (state, batch?.moreComing ?? false)
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
