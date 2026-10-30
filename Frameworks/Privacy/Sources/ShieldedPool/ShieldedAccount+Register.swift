public import Transactions

extension ShieldedAccount {
    /// Creates the user-registry instruction that publishes the account's shielded address.
    ///
    /// - Parameter payer: The wallet that pays the record's rent and signs.
    /// - Returns: The registration instruction.
    /// - Throws: ``Recipient/ValidationError/offCurveSigningAddress`` if the signing address isn't an
    ///   Ed25519 point, or a ``Transactions/ValidationError`` if an account's derivation fails.
    public func register(paidBy payer: Address) throws -> Instruction {
        try UserRegistry.register(recipient, paidBy: payer)
    }
}
