import Encoding

/// An AWS Nitro Enclaves attestation document, the payload of the message the Nitro Secure Module signs.
struct NitroAttestationDocument: Sendable {
    private static let maximumFieldCount = 16

    private static let pcrIndices: Range<Int64> = 0..<32

    private static let sha384 = "SHA384"

    private static let pcrByteCount = 48

    /// The PCR0 of a debug enclave.
    private static let debugPCR0 = [UInt8](repeating: 0, count: pcrByteCount)

    private static let maximumBundleCount = 8

    /// PCR0 through PCR2, which measure the enclave image.
    let measurement: NitroPolicy.Measurement

    /// The DER of the certificate that signs the document.
    let certificate: [UInt8]

    /// The DER of the issuing certificates, `cabundle`, from the root down.
    let bundle: [[UInt8]]

    /// The public key the enclave asked the module to include, or `nil` for none.
    let publicKey: [UInt8]?

    /// The data the enclave asked the module to include, or `nil` for none.
    let userData: [UInt8]?

    /// The nonce the enclave asked the module to include, or `nil` for none.
    let nonce: [UInt8]?

    /// Decodes a document.
    ///
    /// - Parameter payload: The encoded document.
    /// - Throws: ``NitroPolicy/ValidationError/malformed`` for bytes outside the strict CBOR subset, a map of more than
    ///   16 fields, or a document without a non-empty text `module_id`, a non-negative integer `timestamp`, a text
    ///   `digest`, `pcrs` of byte strings indexed below 32 with 48-byte PCR0 through PCR2, a byte-string
    ///   `certificate`, and a `cabundle` of at most 8 byte strings, or with a `public_key`, `user_data`, or `nonce`
    ///   other than a byte string or null; ``NitroPolicy/ValidationError/unsupportedDigest`` for a `digest` other
    ///   than `SHA384`; or ``NitroPolicy/ValidationError/debugEnclave`` for a zero PCR0.
    init(decoding payload: [UInt8]) throws {
        guard case .map(let fields) = try? CBOR(decoding: payload), fields.count <= Self.maximumFieldCount,
            case .text(let moduleID)? = fields[.text("module_id")], !moduleID.isEmpty,
            case .integer(let timestamp)? = fields[.text("timestamp")], timestamp >= 0,
            case .text(let digest)? = fields[.text("digest")],
            case .map(let pcrs)? = fields[.text("pcrs")],
            case .bytes(let certificate)? = fields[.text("certificate")],
            case .array(let bundle)? = fields[.text("cabundle")], bundle.count <= Self.maximumBundleCount
        else { throw NitroPolicy.ValidationError.malformed }
        guard digest == Self.sha384 else { throw NitroPolicy.ValidationError.unsupportedDigest }
        var registers: [Int64: [UInt8]] = [:]
        for (key, value) in pcrs {
            guard case .integer(let index) = key, Self.pcrIndices.contains(index), case .bytes(let pcr) = value else {
                throw NitroPolicy.ValidationError.malformed
            }
            registers[index] = pcr
        }
        guard let pcr0 = registers[0], let pcr1 = registers[1], let pcr2 = registers[2],
            [pcr0, pcr1, pcr2].allSatisfy({ $0.count == Self.pcrByteCount })
        else { throw NitroPolicy.ValidationError.malformed }
        guard pcr0 != Self.debugPCR0 else { throw NitroPolicy.ValidationError.debugEnclave }
        measurement = NitroPolicy.Measurement(pcr0: pcr0, pcr1: pcr1, pcr2: pcr2)
        self.certificate = certificate
        self.bundle = try bundle.map { item in
            guard case .bytes(let certificate) = item else { throw NitroPolicy.ValidationError.malformed }
            return certificate
        }
        publicKey = try Self.optionalBytes(fields[.text("public_key")])
        userData = try Self.optionalBytes(fields[.text("user_data")])
        nonce = try Self.optionalBytes(fields[.text("nonce")])
    }

    /// Reads an optional byte-string field.
    ///
    /// - Parameter value: The field's value, or `nil` for an absent field.
    /// - Returns: The bytes, or `nil` for an absent or null field.
    /// - Throws: ``NitroPolicy/ValidationError/malformed`` for a value other than a byte string or null.
    private static func optionalBytes(_ value: CBOR?) throws -> [UInt8]? {
        switch value {
        case nil, .null?: nil
        case .bytes(let bytes)?: bytes
        default: throw NitroPolicy.ValidationError.malformed
        }
    }
}
