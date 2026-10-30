import Testing

struct NonzeroHashChainVectors: Decodable, Sendable {
    let vectors: [Chain]

    struct Chain: Decodable, Sendable, CustomTestStringConvertible {
        let name: String
        let inputs: [String]
        let output: String

        var testDescription: String { name }
    }

    static func load() throws -> Self {
        try fixture(named: "NonzeroHashChainVectors")
    }
}
