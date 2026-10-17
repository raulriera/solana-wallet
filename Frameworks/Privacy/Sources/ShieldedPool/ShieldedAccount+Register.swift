public import Transactions

extension ShieldedAccount {
    /// Creates the user-registry instruction that publishes the account's shielded address: its
    /// nullifier public key and compressed viewing public key under its signing address.
    ///
    /// Others look the address up with ``Recipient/lookup(_:using:)`` to send to the account. The
    /// account signs as the record's owner, and the payer, which may be the account, funds the
    /// record's rent. The instruction fails if the record exists; read
    /// ``registration(using:)`` first. A record is permanent.
    ///
    /// - Parameter payer: The wallet that pays the record's rent and signs.
    /// - Returns: The instruction, which can share a transaction with a deposit.
    /// - Throws: ``Recipient/ValidationError/offCurveSigningAddress`` if the signing address isn't an
    ///   Ed25519 point, or a ``Transactions/ValidationError`` if an account's derivation fails, which
    ///   doesn't happen.
    public func register(paidBy payer: Address) throws -> Instruction {
        try UserRegistry.register(recipient, paidBy: payer)
    }
}
