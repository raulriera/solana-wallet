import CryptoKit
import Encoding
import Testing
@testable import Attestation

struct NitroCBORCases: Decodable, Sendable {
    let now: Int
    let nonce: String
    let hpkePublicKey: String
    let policy: NitroPolicyFixture
    let root: String
    let leafKey: String
    let cases: [Case]

    private enum CodingKeys: String, CodingKey {
        case now
        case nonce
        case hpkePublicKey = "hpke_public_key"
        case policy
        case root
        case leafKey = "leaf_key"
        case cases
    }

    struct Case: Decodable, Sendable, CustomTestStringConvertible {
        let name: String
        let cose: String?
        let payload: String?
        let expect: Expectation

        var testDescription: String { name }
    }

    enum Expectation: String, Decodable, Sendable {
        case accept
        case reject
    }

    private static let decoded = Result { try fixture(named: "NitroCBORCases") as Self }

    static func load() throws -> Self {
        try decoded.get()
    }

    static func cases(expected expectation: Expectation) throws -> [Case] {
        try load().cases.filter { $0.expect == expectation }
    }

    static func messages(expected expectation: Expectation) throws -> [Case] {
        try cases(expected: expectation).filter { $0.cose != nil }
    }

    func trustedPolicy() throws -> NitroPolicy {
        try policy.policy(root: fixtureBytes(root))
    }

    func documentFields() throws -> [CBOR.Key: CBOR] {
        let payload = try #require(cases.first { $0.name == "the fixture document" }?.payload)
        guard case .map(let fields) = try CBOR(decoding: fixtureBytes(payload)) else {
            throw CBOR.ValidationError.malformed
        }
        return fields
    }

    func message(of testCase: Case) throws -> [UInt8] {
        if let cose = testCase.cose {
            return try fixtureBytes(cose)
        }
        return try signed(fixtureBytes(try #require(testCase.payload)))
    }

    func signed(_ payload: [UInt8], algorithm: Int64 = -35) throws -> [UInt8] {
        let key = try P384.Signing.PrivateKey(rawRepresentation: fixtureBytes(leafKey))
        let header = CBOR.map([.integer(1): .integer(algorithm)]).encoded
        let signature = try key.signature(for: COSESign1.signatureStructure(protectedHeader: header, payload: payload))
        let fields: [CBOR] = [.bytes(header), .map([:]), .bytes(payload), .bytes(Array(signature.rawRepresentation))]
        return [0xd2] + CBOR.array(fields).encoded
    }
}
