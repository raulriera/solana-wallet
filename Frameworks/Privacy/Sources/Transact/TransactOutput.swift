import ModularArithmetic

/// One output slot of a transact as the instruction publishes it.
struct TransactOutput: Sendable, Equatable {
    /// The way an output names its view tag.
    enum OwnerTag: Sendable, Equatable {
        /// The 32-byte view tag, written in the output.
        case inline([UInt8])
        /// A reference to the fee payer's account.
        case payer
    }

    private static let inlineVariant: UInt8 = 0

    private static let accountVariant: UInt8 = 1

    private static let payerAccountIndex: UInt8 = 0

    let utxoHash: Poseidon.Element

    let ownerTag: OwnerTag

    /// The sealed note, or random bytes of the same length for padding.
    let data: [UInt8]

    /// Writes the UTXO hash, the owner tag, and the payload as a present byte vector.
    ///
    /// - Parameter writer: The writer that receives the output.
    /// - Throws: ``WincodeWriter/ValidationError/lengthOverflow`` if the payload exceeds 65,535 bytes.
    func write(to writer: inout WincodeWriter) throws {
        writer.append(array: utxoHash.bigEndianBytes)
        switch ownerTag {
        case .inline(let viewTag):
            precondition(viewTag.count == 32, "A view tag needs exactly 32 bytes.")
            writer.append(Self.inlineVariant)
            writer.append(array: viewTag)
        case .payer:
            writer.append(Self.accountVariant)
            writer.append(Self.payerAccountIndex)
        }
        try writer.appendSome(vector: data)
    }
}
