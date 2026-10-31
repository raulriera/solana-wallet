import Testing

struct NitroCBORCases: Decodable, Sendable {
    let leafKey: String
    let cases: [Case]

    private enum CodingKeys: String, CodingKey {
        case leafKey = "leaf_key"
        case cases
    }

    struct Case: Decodable, Sendable, CustomTestStringConvertible {
        let name: String
        let cose: String?
        let expect: Expectation

        var testDescription: String { name }
    }

    enum Expectation: String, Decodable, Sendable {
        case accept
        case reject
    }

    static func load() throws -> Self {
        try fixture(named: "NitroCBORCases")
    }

    static func messages(expected expectation: Expectation) throws -> [Case] {
        try load().cases.filter { $0.cose != nil && $0.expect == expectation }
    }
}
