import Encoding
@testable import Attestation

extension RecordedNitroAttestation {
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
