import Testing
import RPC

/// Verifies the identity of shielded transactions.
struct ShieldedTransactionTests {
    /// The output the fixtures carry.
    private static let output = ShieldedOutput(viewTag: [1], utxoHash: [2], treeID: 0, leafIndex: 0, payload: [])

    /// Creates a confidential transaction with optional changes.
    /// - Parameters:
    ///   - signature: The signature.
    ///   - slot: The slot.
    ///   - eventIndex: The event index.
    ///   - salt: The salt.
    ///   - nullifiers: The nullifiers.
    ///   - isProofless: Whether it is a deposit.
    /// - Returns: The transaction.
    private static func transaction(signature: String = "s", slot: UInt64 = 1, eventIndex: UInt16? = 0,
                                    salt: [UInt8]? = [7], nullifiers: [[UInt8]] = [[8]],
                                    isProofless: Bool = false) -> ShieldedTransaction {
        ShieldedTransaction(signature: signature, slot: slot, eventIndex: eventIndex, transactionViewingKey: [6],
                            salt: salt, outputs: [output], nullifiers: nullifiers, isProofless: isProofless)
    }

    /// Verifies transactions are equal only when every published field is.
    ///
    /// - Parameter other: The transaction with one field changed.
    @Test(arguments: [
        transaction(signature: "t"), transaction(slot: 2), transaction(eventIndex: nil), transaction(salt: nil),
        transaction(nullifiers: []), transaction(isProofless: true),
    ])
    func `Transactions differ when any published field differs`(other: ShieldedTransaction) {
        #expect(other != Self.transaction())
        #expect(Self.transaction() == Self.transaction())
    }
}
