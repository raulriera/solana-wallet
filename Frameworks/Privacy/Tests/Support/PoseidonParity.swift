import CryptoKit
import Testing

struct PoseidonParity: Decodable, Sendable {
    let parameters: Parameters

    let vectors: [Vector]

    struct Parameters: Decodable, Sendable {
        let roundsFull: Int
        let perArity: [Width]
    }

    struct Width: Decodable, Sendable, CustomTestStringConvertible {
        let width: Int
        let roundsPartial: Int
        let arkCount: Int
        let arkSha256: String
        let mdsSha256: String

        var testDescription: String { "Width \(width)" }

        var roundConstantDigest: [UInt8] {
            get throws { try fixtureBytes(arkSha256) }
        }

        var matrixDigest: [UInt8] {
            get throws { try fixtureBytes(mdsSha256) }
        }
    }

    struct Vector: Decodable, Sendable, CustomTestStringConvertible {
        let id: String
        let inputsBytes: [String]
        let expectedBytes: String

        var testDescription: String { id }
    }

    static func load() throws -> Self {
        try fixture(named: "PoseidonParity")
    }

    static func digest(of values: some Sequence<[UInt8]>) -> [UInt8] {
        Array(SHA256.hash(data: Array(values.joined())))
    }
}
