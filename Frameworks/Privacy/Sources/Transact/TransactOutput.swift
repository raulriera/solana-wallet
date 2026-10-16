import ModularArithmetic

/// One output slot of a transact, as the instruction publishes it: the commitment, the owner tag,
/// and the payload.
///
/// The UTXO tree appends the commitment. The owner tag resolves to the view tag that the slot
/// publishes: the owner's signing address, or a participant's for a padding slot. A slot that the
/// fee payer owns refers to the payer's account instead of repeating its 32 bytes. The payload is
/// the ``ConfidentialOutput`` note, or random bytes of the same length for padding.
struct TransactOutput: Sendable, Equatable {
    /// How an output names its view tag.
    enum OwnerTag: Sendable, Equatable {
        /// The 32-byte view tag, written in the output, `OwnerTag::Inline`.
        case inline([UInt8])
        /// The fee payer's address, the instruction's account 0, `OwnerTag::Account(0)`.
        case payer
    }

    /// The variant of an inline owner tag.
    private static let inlineVariant: UInt8 = 0

    /// The variant of an owner tag that refers to an account.
    private static let accountVariant: UInt8 = 1

    /// The index of the fee payer's account.
    private static let payerAccountIndex: UInt8 = 0

    /// The UTXO hash that the tree appends.
    let utxoHash: Poseidon.Element

    /// The owner tag.
    let ownerTag: OwnerTag

    /// The payload of the output's data slot.
    let data: [UInt8]

    /// Writes the output: the UTXO hash, the owner tag's variant and value, and the payload as a
    /// present byte vector.
    ///
    /// - Parameter writer: The writer that receives the output.
    /// - Throws: ``WincodeWriter/ValidationError/lengthOverflow`` if the payload exceeds 65,535 bytes.
    /// - Precondition: An inline owner tag has exactly 32 bytes.
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
