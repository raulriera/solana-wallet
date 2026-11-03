import Attestation
import CryptoKit
import Foundation

struct RecordedNitroAttestation: Decodable, Sendable {
    let capturedAt: Int
    let nonce: String
    let attestation: Attestation

    private enum CodingKeys: String, CodingKey {
        case capturedAt = "captured_at"
        case nonce
        case attestation
    }

    struct Attestation: Decodable, Sendable {
        let platform: String
        let hpkePublicKey: String
        let evidence: Evidence

        private enum CodingKeys: String, CodingKey {
            case platform
            case hpkePublicKey = "hpke_public_key"
            case evidence
        }
    }

    struct Evidence: Decodable, Sendable {
        let document: String
    }

    static func load(named name: String) throws -> Self {
        try fixture(named: name)
    }

    var capturedDate: Date {
        Date(timeIntervalSince1970: TimeInterval(capturedAt))
    }

    var hpkePublicKey: [UInt8] {
        get throws { try fixtureBytes(attestation.hpkePublicKey) }
    }

    var responseObject: [String: Any] {
        [
            "platform": attestation.platform,
            "hpke_public_key": attestation.hpkePublicKey,
            "gpu": NSNull(),
            "evidence": ["document": attestation.evidence.document],
        ]
    }

    func responseBody() throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: responseObject), as: UTF8.self)
    }

    func publicKey(
        under policy: NitroPolicy,
        userData: [UInt8],
        at date: Date? = nil
    ) throws -> Curve25519.KeyAgreement.PublicKey {
        try Curve25519.KeyAgreement.PublicKey(
            rawRepresentation: hpkePublicKey,
            attestedBy: fixtureBytes(attestation.evidence.document),
            nonce: fixtureBytes(nonce),
            userData: userData,
            policy: policy,
            at: date ?? capturedDate
        )
    }
}
