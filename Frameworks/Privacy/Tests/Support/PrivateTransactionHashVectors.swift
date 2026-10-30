import Testing

struct PrivateTransactionHashVectors: Decodable, Sendable {
    let vectors: [Hash]

    struct Hash: Decodable, Sendable, CustomTestStringConvertible {
        let name: String
        let inputHashes: [String]
        let outputHashes: [String]
        let addressNullifiers: [String]
        let blinding: String
        let privateTransactionHash: String

        private enum CodingKeys: String, CodingKey {
            case name
            case inputHashes = "input_hashes"
            case outputHashes = "output_hashes"
            case addressNullifiers = "address_nullifiers"
            case blinding
            case privateTransactionHash = "private_tx_hash"
        }

        var testDescription: String { name }

        var createsNoAddress: Bool { addressNullifiers.allSatisfy { $0.allSatisfy { $0 == "0" } } }
    }

    static func load() throws -> Self {
        try fixture(named: "PrivateTransactionHashVectors")
    }
}
