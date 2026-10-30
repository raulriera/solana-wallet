import Testing

struct ProvingKeyVectors: Decodable, Sendable {
    let keys: [String: Key]

    struct Key: Decodable, Sendable {
        let sha256: String
    }

    static func load() throws -> Self {
        try fixture(named: "ProvingKeyVectors")
    }
}
