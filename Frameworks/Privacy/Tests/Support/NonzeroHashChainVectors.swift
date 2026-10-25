import Testing

/// zolana's nonzero hash chain vectors.
///
/// `NonzeroHashChainVectors.json` copies `test-vectors/nonzero_hash_chain.json` unchanged at tag
/// v0.4.0-alpha (Apache-2.0). `NOTICE.txt` records the source and its
/// digest. Elements and chains are 32-byte big-endian hexadecimal field elements.
struct NonzeroHashChainVectors: Decodable, Sendable {
    /// The chains, from empty lists to 36 elements, with zeros in several positions.
    let vectors: [Chain]

    /// A list of elements and its chain.
    struct Chain: Decodable, Sendable, CustomTestStringConvertible {
        /// The vector's name in the fixture.
        let name: String
        /// The elements, in order.
        let inputs: [String]
        /// The chain.
        let output: String

        /// The vector's name, in test results.
        var testDescription: String { name }
    }

    /// Reads the fixture from the test bundle.
    ///
    /// - Returns: The chain vectors.
    /// - Throws: A test failure if the resource is missing, or an error if it can't be read or decoded.
    static func load() throws -> Self {
        try fixture(named: "NonzeroHashChainVectors")
    }
}
