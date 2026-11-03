import CryptoKit
import Encoding
import Foundation
import Testing
@testable import Attestation

struct Curve25519NitroAttestationTests {
    private struct Attempt {
        var key: [UInt8]
        var message: [UInt8]
        var nonce: [UInt8]
        var userData: [UInt8]
        var policy: NitroPolicy
        var date: Date

        func verified() throws -> Curve25519.KeyAgreement.PublicKey {
            try Curve25519.KeyAgreement.PublicKey(
                rawRepresentation: key,
                attestedBy: message,
                nonce: nonce,
                userData: userData,
                policy: policy,
                at: date
            )
        }
    }

    @Test(arguments: try NitroCBORCases.cases(expected: .accept))
    func `Recorded cases that the contract accepts verify`(testCase: NitroCBORCases.Case) throws {
        let cases = try NitroCBORCases.load()
        let attempt = try Self.attempt(message: cases.message(of: testCase))

        #expect(Array(try attempt.verified().rawRepresentation) == (try fixtureBytes(cases.hpkePublicKey)))
    }

    @Test(arguments: try NitroCBORCases.cases(expected: .reject))
    func `Recorded cases that the contract rejects are malformed`(testCase: NitroCBORCases.Case) throws {
        let attempt = try Self.attempt(message: NitroCBORCases.load().message(of: testCase))

        #expect(throws: NitroPolicy.ValidationError.malformed) { try attempt.verified() }
    }

    @Test
    func `A policy with the AWS root rejects a chain to another root`() throws {
        var attempt = try Self.attempt()
        attempt.policy = NitroPolicy(
            measurements: attempt.policy.measurements,
            publicKey: nil,
            maximumAge: attempt.policy.maximumAge
        )

        #expect(throws: NitroPolicy.ValidationError.untrustedCertificateChain) { try attempt.verified() }
    }

    @Test
    func `A document whose certificates expired is rejected`() throws {
        let recorded = try RecordedNitroAttestation.load(named: "RecordedDevnetNitroAttestation")
        let policy = NitroPolicy(measurements: [], publicKey: nil, maximumAge: 0)

        #expect(throws: NitroPolicy.ValidationError.untrustedCertificateChain) {
            try recorded.publicKey(under: policy, userData: [], at: .distantFuture)
        }
    }

    @Test
    func `A message the document's certificate didn't sign is rejected`() throws {
        var attempt = try Self.attempt()
        attempt.message[attempt.message.count - 1] ^= 0x01

        #expect(throws: NitroPolicy.ValidationError.invalidSignature) { try attempt.verified() }
    }

    @Test
    func `A message signed with an algorithm other than ES384 is rejected`() throws {
        let cases = try NitroCBORCases.load()
        let payload = CBOR.map(try cases.documentFields()).encoded
        let attempt = try Self.attempt(message: cases.signed(payload, algorithm: -7))

        #expect(throws: NitroPolicy.ValidationError.unsupportedAlgorithm) { try attempt.verified() }
    }

    @Test
    func `A document the policy doesn't allow is rejected`() throws {
        var attempt = try Self.attempt()
        attempt.policy = NitroPolicy(
            measurements: [],
            publicKey: nil,
            root: attempt.policy.root,
            maximumAge: attempt.policy.maximumAge
        )

        #expect(throws: NitroPolicy.ValidationError.unexpectedMeasurement) { try attempt.verified() }
    }

    @Test
    func `A claimed key the policy doesn't pin is rejected`() throws {
        var attempt = try Self.attempt()
        let other = [UInt8](repeating: 0x0f, count: 32)
        attempt.policy = NitroPolicy(
            measurements: attempt.policy.measurements,
            publicKey: other,
            root: attempt.policy.root,
            maximumAge: attempt.policy.maximumAge
        )

        #expect(throws: NitroPolicy.ValidationError.unexpectedPublicKey) { try attempt.verified() }
    }

    @Test(
        arguments: [
            ("public_key", .publicKeyMismatch),
            ("nonce", .nonceMismatch),
            ("user_data", .userDataMismatch),
        ] as [(field: String, error: NitroPolicy.ValidationError)],
        [.bytes([UInt8](repeating: 0x0f, count: 32)), .null, nil] as [CBOR?]
    )
    func `A document that doesn't bind the client's values is rejected`(
        binding: (field: String, error: NitroPolicy.ValidationError),
        value: CBOR?
    ) throws {
        var fields = try NitroCBORCases.load().documentFields()
        fields[.text(binding.field)] = value

        #expect(throws: binding.error) { try Self.attempt(signing: fields).verified() }
    }

    @Test
    func `A claimed key that isn't 32 bytes is rejected`() throws {
        var attempt = try Self.attempt()
        attempt.key.removeLast()

        #expect(throws: CryptoKitError.incorrectKeySize) { try attempt.verified() }
    }

    @Test(arguments: [31, 33])
    func `A nonce that isn't 32 bytes is rejected`(count: Int) throws {
        var attempt = try Self.attempt()
        attempt.nonce = [UInt8](repeating: 0x11, count: count)

        #expect(throws: CryptoKitError.incorrectParameterSize) { try attempt.verified() }
    }

    private static func attempt(message: [UInt8]) throws -> Attempt {
        let cases = try NitroCBORCases.load()
        return Attempt(
            key: try fixtureBytes(cases.hpkePublicKey),
            message: message,
            nonce: try fixtureBytes(cases.nonce),
            userData: try fixtureBytes(cases.userData),
            policy: try cases.trustedPolicy(),
            date: Date(timeIntervalSince1970: TimeInterval(cases.now))
        )
    }

    private static func attempt(signing fields: [CBOR.Key: CBOR]? = nil) throws -> Attempt {
        let cases = try NitroCBORCases.load()
        return try attempt(message: cases.signed(CBOR.map(fields ?? cases.documentFields()).encoded))
    }
}
