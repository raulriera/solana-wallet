import Encoding
import Foundation
import Testing
@testable import Attestation

struct RecordedNitroAttestation: Decodable, Sendable {
    let capturedAt: Int
    let attestation: Attestation

    private enum CodingKeys: String, CodingKey {
        case capturedAt = "captured_at"
        case attestation
    }

    struct Attestation: Decodable, Sendable {
        let evidence: Evidence
    }

    struct Evidence: Decodable, Sendable {
        let document: String
    }

    static func load() throws -> Self {
        try fixture(named: "RecordedNitroAttestation")
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
}
