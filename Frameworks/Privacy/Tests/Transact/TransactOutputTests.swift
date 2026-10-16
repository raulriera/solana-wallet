import ModularArithmetic
@testable import Privacy
import Testing

/// Verifies the encoding of transact outputs.
struct TransactOutputTests {
    /// Verifies an inline owner tag: the hash, the variant 0, the 32-byte view tag, and the payload
    /// as a present byte vector.
    @Test
    func `Inline owner tags write the view tag`() throws {
        let hash = Poseidon.Element(0x0102)
        var writer = WincodeWriter()
        try TransactOutput(utxoHash: hash, ownerTag: .inline(Array(repeating: 9, count: 32)), data: [0xaa, 0xbb]).write(to: &writer)

        #expect(writer.bytes == hash.bigEndianBytes + [0] + Array(repeating: 9, count: 32) + [1, 2, 0, 0xaa, 0xbb])
    }

    /// Verifies a payer owner tag: the hash, the variant 1, the account index 0, and the payload.
    @Test
    func `Payer owner tags refer to account 0`() throws {
        let hash = Poseidon.Element(0x0102)
        var writer = WincodeWriter()
        try TransactOutput(utxoHash: hash, ownerTag: .payer, data: Array(repeating: 5, count: 89)).write(to: &writer)

        #expect(writer.bytes == hash.bigEndianBytes + [1, 0, 1, 89, 0] + Array(repeating: 5, count: 89))
    }

    /// Verifies that a payload beyond a 16-bit length is rejected.
    @Test
    func `Payloads beyond a 16-bit length are rejected`() {
        var writer = WincodeWriter()

        #expect(throws: WincodeWriter.ValidationError.lengthOverflow) {
            try TransactOutput(utxoHash: .one, ownerTag: .payer, data: Array(repeating: 0, count: 65_536)).write(to: &writer)
        }
    }
}
