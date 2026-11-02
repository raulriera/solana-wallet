import Encoding
import RPC

extension ShieldedPool {
    private static let ringTransactTag: UInt8 = 19

    private static let ringMergeTransactTag: UInt8 = 20

    private static let ringAuthorityTransactTag: UInt8 = 21

    /// The circuit IDs that the program accepts in a transact.
    private static let transactCircuits: Set<UInt16> = [TransactPlan.confidentialSignerCircuit, 1, 2, 4, 5, 7, 8]

    /// The circuit IDs whose payload holds a BSB22 commitment, its proof of knowledge, and the owner's key.
    private static let eddsaCircuits: Set<UInt16> = [7, 8]

    /// The circuit IDs whose payload holds a cache selection: a read bitmap and sixteen write slots.
    private static let cachedCircuits: Set<UInt16> = [4, 5, 8]

    /// The optional hashes of a transact's external data: its data hash and its ring data hash.
    private static let optionalHashCount = 2

    /// The interface transfer kinds that hold only an amount: SOL deposits and withdrawals.
    private static let solTransferKinds: Set<UInt8> = [0, ExternalData.solWithdrawalVariant]

    /// The interface transfer kinds that hold an amount and an SPL interface bump: SPL deposits and withdrawals.
    private static let splTransferKinds: Set<UInt8> = [2, 3]

    /// The merge output encryption scheme that the program accepts: Poseidon counter mode.
    private static let mergeEncryptionScheme: UInt8 = 1

    /// The bytes of a tagged X25519 transaction viewing public key.
    private static let taggedKeyLength = 33

    /// The bytes of a transact circuit's numbers of input and output slots and public asset slots.
    private static let shapeLength = 3

    /// The bytes of a nullifier, a UTXO hash, a view tag, a private transaction hash, or a field element.
    private static let hashLength = 32

    /// The bytes of an EdDSA circuit's payload: its BSB22 commitment, the commitment's proof of knowledge, and the
    /// owner's key.
    private static let eddsaPayloadLength = 3 * hashLength

    /// The bytes of a cached circuit's payload: its 64-bit read bitmap and sixteen output and slot pairs.
    private static let cachePayloadLength = 8 + 16 * 2

    /// The bytes of a merge output's three ciphertext field elements.
    private static let mergeCiphertextLength = 3 * hashLength

    /// The bytes of one tree context, or of a merge's root indices: a UTXO and a nullifier root index.
    private static let rootIndicesLength = 4

    /// Reads the nullifiers that a transaction's shielded-pool spend instructions spend.
    ///
    /// - Parameter transaction: The transaction whose top-level and invoked instructions to read.
    /// - Returns: The 32-byte nullifiers of each transact, ring transact, ring authority transact, merge transact, and
    ///   ring merge transact instruction of the shielded-pool program whose data follows its layout; other instructions
    ///   add none.
    static func nullifiers(spentBy transaction: GetTransaction.Value) -> Set<[UInt8]> {
        Set(transaction.instructionData(invoking: programID).flatMap { data in
            (try? spentNullifiers(in: [UInt8](data))) ?? []
        })
    }

    /// Reads the nullifiers that a shielded-pool instruction's data spends.
    ///
    /// - Parameter data: The instruction data.
    /// - Returns: The 32-byte nullifiers in input order, or none for an instruction that doesn't spend.
    /// - Throws: ``MalformedSpend`` for spend data that doesn't follow its layout.
    private static func spentNullifiers(in data: [UInt8]) throws -> [[UInt8]] {
        guard let tag = data.first else { return [] }
        var reader = ByteReader(data, at: 1, error: MalformedSpend())
        let nullifiers: [[UInt8]]
        switch tag {
        case transactTag, ringTransactTag, ringAuthorityTransactTag: nullifiers = try transactNullifiers(reading: &reader)
        case mergeTransactTag, ringMergeTransactTag: nullifiers = try mergeNullifiers(reading: &reader)
        default: return []
        }
        guard reader.isAtEnd else { throw MalformedSpend() }
        return nullifiers
    }

    /// Reads the input nullifiers of transact data after its tag.
    ///
    /// - Parameter reader: The reader, which ends after the data's last tree context.
    /// - Returns: The 32-byte input nullifiers, in input order.
    /// - Throws: ``MalformedSpend`` for data that doesn't follow the transact layout.
    private static func transactNullifiers(reading reader: inout ByteReader) throws -> [[UInt8]] {
        _ = try reader.integer() as UInt64
        try reader.skip(taggedKeyLength + SlotCipher.saltLength)
        for _ in 0..<(try reader.count()) {
            let kind: UInt8 = try reader.integer()
            guard solTransferKinds.contains(kind) || splTransferKinds.contains(kind) else { throw MalformedSpend() }
            _ = try reader.integer() as UInt64
            if splTransferKinds.contains(kind) { _ = try reader.integer() as UInt8 }
        }
        for _ in 0..<optionalHashCount where try reader.isPresent() {
            try reader.skip(hashLength)
        }
        for _ in 0..<(try reader.count()) {
            try reader.skip(hashLength)
            switch try reader.integer() as UInt8 {
            case TransactOutput.inlineVariant: try reader.skip(hashLength)
            case TransactOutput.accountVariant: _ = try reader.integer() as UInt8
            default: throw MalformedSpend()
            }
            if try reader.isPresent() { try reader.skipVector() }
        }
        for _ in 0..<(try reader.count()) {
            try reader.skip(hashLength)
            try reader.skipVector()
        }
        try reader.skip(hashLength)
        let circuit: UInt16 = try reader.integer()
        guard transactCircuits.contains(circuit) else { throw MalformedSpend() }
        try reader.skip(shapeLength)
        if eddsaCircuits.contains(circuit) { try reader.skip(eddsaPayloadLength) }
        if cachedCircuits.contains(circuit) { try reader.skip(cachePayloadLength) }
        try reader.skip(TransactProof.length)
        let nullifiers = try (0..<(try reader.count())).map { _ in
            let nullifier = [UInt8](try reader.read(count: hashLength))
            _ = try reader.integer() as UInt8
            return nullifier
        }
        try reader.skip(rootIndicesLength * (try reader.count()))
        return nullifiers
    }

    /// Reads the nullifiers of merge transact data after its tag.
    ///
    /// - Parameter reader: The reader, which ends after the data's cache slot.
    /// - Returns: The 32-byte nullifiers, in order.
    /// - Throws: ``MalformedSpend`` for data that doesn't follow the merge layout.
    private static func mergeNullifiers(reading reader: inout ByteReader) throws -> [[UInt8]] {
        _ = try reader.integer() as UInt64
        try reader.skip(TransactProof.length + hashLength)
        guard try reader.integer() as UInt8 == mergeEncryptionScheme else { throw MalformedSpend() }
        try reader.skip(SlotCipher.saltLength + mergeCiphertextLength + hashLength)
        let nullifiers = try (0..<(try reader.count())).map { _ in [UInt8](try reader.read(count: hashLength)) }
        try reader.skip(rootIndicesLength)
        if try reader.isPresent() { _ = try reader.integer() as UInt8 }
        return nullifiers
    }
}

extension ByteReader {
    /// Reads past bytes.
    ///
    /// - Parameter count: The number of bytes.
    /// - Throws: The reader's error if fewer bytes remain.
    fileprivate mutating func skip(_ count: Int) throws {
        _ = try read(count: count)
    }

    /// Reads a one-byte element count.
    ///
    /// - Returns: The count.
    /// - Throws: The reader's error if no byte remains.
    fileprivate mutating func count() throws -> Int {
        Int(try integer() as UInt8)
    }

    /// Reads whether an option is present.
    ///
    /// - Returns: Whether the option's value follows.
    /// - Throws: The reader's error if no byte remains, or ``MalformedSpend`` for a byte other than 0 or 1.
    fileprivate mutating func isPresent() throws -> Bool {
        switch try integer() as UInt8 {
        case 0: false
        case 1: true
        default: throw MalformedSpend()
        }
    }

    /// Reads past a byte vector: its little-endian 16-bit length and its bytes.
    ///
    /// - Throws: The reader's error if the vector is truncated.
    fileprivate mutating func skipVector() throws {
        try skip(Int(try integer() as UInt16))
    }
}

/// Spend instruction data that doesn't follow the shielded-pool program's layout.
private struct MalformedSpend: Error {}
