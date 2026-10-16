import Testing

/// zolana's private transaction hash vectors.
///
/// `PrivateTransactionHashVectors.json` copies `test-vectors/private_tx_hash.json` unchanged at tag
/// v0.4.0-alpha (Apache-2.0). `PrivateTransactionHashVectors-LICENSE.txt` records the source and its
/// digest. Every value is a 32-byte big-endian hexadecimal field element. The fixture also publishes
/// each vector's message hash, which only P-256 owners sign, so the decoding leaves it out.
struct PrivateTransactionHashVectors: Decodable, Sendable {
    /// The hashes, including padding at different positions, reordered inputs, address nullifiers,
    /// and r - 1 values.
    let vectors: [Hash]

    /// A transact's slots, blinding, and private transaction hash.
    struct Hash: Decodable, Sendable, CustomTestStringConvertible {
        /// The vector's name in the fixture.
        let name: String
        /// The input slots' UTXO hashes, zero for padding.
        let inputHashes: [String]
        /// The output slots' UTXO hashes, zero for padding.
        let outputHashes: [String]
        /// The address nullifiers, one per input slot, zero where no address is created.
        let addressNullifiers: [String]
        /// The private transaction blinding.
        let blinding: String
        /// The private transaction hash.
        let privateTransactionHash: String

        /// The fixture's JSON keys.
        private enum CodingKeys: String, CodingKey {
            case name
            case inputHashes = "input_hashes"
            case outputHashes = "output_hashes"
            case addressNullifiers = "address_nullifiers"
            case blinding
            case privateTransactionHash = "private_tx_hash"
        }

        /// The vector's name, in test results.
        var testDescription: String { name }

        /// Whether the transact creates no address, as every peer-to-peer transfer does.
        var createsNoAddress: Bool { addressNullifiers.allSatisfy { $0.allSatisfy { $0 == "0" } } }
    }

    /// Reads the fixture from the test bundle.
    ///
    /// - Returns: The hash vectors.
    /// - Throws: A test failure if the resource is missing, or an error if it can't be read or decoded.
    static func load() throws -> Self {
        try fixture(named: "PrivateTransactionHashVectors")
    }
}
