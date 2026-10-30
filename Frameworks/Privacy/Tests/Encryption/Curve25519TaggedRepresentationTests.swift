import CryptoKit
import Foundation
import Testing

@testable import Privacy

struct Curve25519TaggedRepresentationTests {
    private static let modulus: [UInt8] = [0xed] + Array(repeating: 0xff, count: 30) + [0x7f]

    @Test(arguments: [
        ("a8c6cdc96a3f47a472674331e76bd7237bceb675e513d4faee8734847d376945",
         "0419078976c68ba992eb10aae97df1e453731a022d6c46eb8a0a4f1c976a0cc20a"),
        ("e03f36001762f5c048bc6f3b7438210f712a29383428568a99761b0591b8e242",
         "044952ebadb88eacc3027ae7c29ed6b02c5e83fbffc23f1893ecde29d42449845b"),
    ])
    func `Published keys round-trip`(secret: String, tagged: String) throws {
        let publicKey = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: fixtureBytes(secret)).publicKey
        let decoded = try Curve25519.KeyAgreement.PublicKey(taggedRepresentation: fixtureBytes(tagged))

        #expect([UInt8](publicKey.taggedRepresentation) == (try fixtureBytes(tagged)))
        #expect(decoded.rawRepresentation == publicKey.rawRepresentation)
    }

    @Test(arguments: [
        [0xec] + Array(repeating: 0xff, count: 30) + [0x7f],
        Array(repeating: 0, count: 32),
    ] as [[UInt8]])
    func `Canonical keys decode, low-order ones included`(u: [UInt8]) throws {
        let key = try Curve25519.KeyAgreement.PublicKey(taggedRepresentation: [4] + u)

        #expect([UInt8](key.rawRepresentation) == u)
    }

    @Test(arguments: [
        ([0] + Array(repeating: 1, count: 32), .invalidParameter),
        ([2] + Array(repeating: 1, count: 32), .invalidParameter),
        ([3] + Array(repeating: 1, count: 32), .invalidParameter),
        ([5] + Array(repeating: 1, count: 32), .invalidParameter),
        ([4] + modulus, .invalidParameter),
        ([4] + Array(repeating: 0, count: 31) + [0x80], .invalidParameter),
        ([4] + Array(repeating: 1, count: 31), .incorrectKeySize),
        ([4] + Array(repeating: 1, count: 33), .incorrectKeySize),
    ] as [([UInt8], CryptoKitError)])
    func `Invalid representations are rejected`(bytes: [UInt8], error: CryptoKitError) {
        #expect(throws: error) {
            try Curve25519.KeyAgreement.PublicKey(taggedRepresentation: bytes)
        }
    }
}
