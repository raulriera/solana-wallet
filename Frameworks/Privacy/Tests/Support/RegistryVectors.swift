import Testing

struct RegistryVectors: Decodable, Sendable {
    let program: String

    let records: [Record]

    struct Record: Decodable, Sendable, CustomTestStringConvertible {
        let name: String
        let owner: String
        let record: String
        let bump: UInt8
        let data: String
        let nullifierPublicKey: String
        let viewingPublicKey: String
        let ownerHash: String

        var testDescription: String { name }
    }

    static func load() throws -> Self {
        try fixture(named: "RegistryVectors")
    }
}
