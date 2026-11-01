import CryptoKit
import Encoding
import Foundation
import Testing
@testable import Attestation

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
        let hpkePublicKey: String
        let evidence: Evidence

        private enum CodingKeys: String, CodingKey {
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

    func decoded() throws -> (message: COSESign1, certificate: [UInt8], bundle: [[UInt8]]) {
        let message = try COSESign1(decoding: fixtureBytes(attestation.evidence.document))
        guard case .map(let document) = try CBOR(decoding: message.payload),
            case .bytes(let certificate)? = document[.text("certificate")],
            case .array(let items)? = document[.text("cabundle")]
        else { throw CBOR.ValidationError.malformed }
        let bundle = try items.map { item in
            guard case .bytes(let bytes) = item else { throw CBOR.ValidationError.malformed }
            return bytes
        }
        return (message, certificate, bundle)
    }

    func publicKey(under policy: NitroPolicy, at date: Date? = nil) throws -> Curve25519.KeyAgreement.PublicKey {
        try Curve25519.KeyAgreement.PublicKey(
            rawRepresentation: fixtureBytes(attestation.hpkePublicKey),
            attestedBy: fixtureBytes(attestation.evidence.document),
            nonce: fixtureBytes(nonce),
            policy: policy,
            at: date ?? capturedDate
        )
    }
}
