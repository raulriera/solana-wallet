import RPC
import Testing

struct ShieldedTransactionTests {
    private static let output = ShieldedOutput(viewTag: [1], utxoHash: [2], treeID: 0, leafIndex: 0, payload: [])

    private static func transaction(signature: String = "s", slot: UInt64 = 1, eventIndex: UInt16? = 0,
                                    salt: [UInt8]? = [7], nullifiers: [[UInt8]] = [[8]],
                                    isProofless: Bool = false) -> ShieldedTransaction {
        ShieldedTransaction(signature: signature, slot: slot, eventIndex: eventIndex, transactionViewingKey: [6],
                            salt: salt, outputs: [output], nullifiers: nullifiers, isProofless: isProofless)
    }

    @Test(arguments: [
        transaction(signature: "t"), transaction(slot: 2), transaction(eventIndex: nil), transaction(salt: nil),
        transaction(nullifiers: []), transaction(isProofless: true),
    ])
    func `Transactions differ when any published field differs`(other: ShieldedTransaction) {
        #expect(other != Self.transaction())
        #expect(Self.transaction() == Self.transaction())
    }
}
