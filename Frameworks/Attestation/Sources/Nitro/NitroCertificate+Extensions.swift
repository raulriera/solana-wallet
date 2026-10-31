import Encoding

extension NitroCertificate {
    /// A certificate extension.
    struct Extension: Equatable, Sendable {
        /// The contents of the extension's OBJECT IDENTIFIER.
        let oid: [UInt8]

        let isCritical: Bool

        /// The DER of the extension's value.
        let value: [UInt8]
    }

    /// The value of a basic constraints extension.
    enum BasicConstraints: Equatable, Sendable {
        /// A certificate authority, which may have at most `maxPathLength` certificate authorities below it, or any
        /// number for `nil`.
        case isCertificateAuthority(maxPathLength: Int?)
        case notCertificateAuthority
    }

    /// The value of a key usage extension, as far as a certificate chain reads it.
    struct KeyUsage: Equatable, Sendable {
        let digitalSignature: Bool
        let keyCertSign: Bool
    }
}

extension NitroCertificate.Extension {
    /// The OBJECT IDENTIFIER contents of the basic constraints extension, 2.5.29.19.
    static let basicConstraintsOID: [UInt8] = [0x55, 0x1d, 0x13]

    /// The OBJECT IDENTIFIER contents of the key usage extension, 2.5.29.15.
    static let keyUsageOID: [UInt8] = [0x55, 0x1d, 0x0f]

    /// Reads an extension.
    ///
    /// - Parameter value: The extension's `Extension` sequence.
    /// - Throws: A ``NitroCertificate/ValidationError`` for another structure, an invalid OID, or a critical flag
    ///   other than TRUE.
    init(decoding value: DER) throws {
        var fields = try value.fields()
        oid = try fields.next().objectIdentifier()
        isCritical = try fields.booleanDefaultingToFalse()
        self.value = try fields.next().primitive(.octetString)
        try fields.finish()
    }
}

extension NitroCertificate.BasicConstraints {
    /// Decodes a basic constraints extension's value.
    ///
    /// - Parameter bytes: The DER of the value.
    /// - Throws: A ``NitroCertificate/ValidationError`` for another structure, a path length without a
    ///   certificate authority, a certificate authority flag other than TRUE, or a path length that `Int` can't
    ///   represent, or a `DER.ValidationError` for bytes that aren't DER.
    init(decoding bytes: [UInt8]) throws {
        var fields = try DER(decoding: bytes).fields()
        let isCertificateAuthority = try fields.booleanDefaultingToFalse()
        let maxPathLength = try fields.next(.integer).map { try $0.intValue() }
        try fields.finish()
        guard isCertificateAuthority || maxPathLength == nil else { throw NitroCertificate.ValidationError.malformed }
        self = isCertificateAuthority ? .isCertificateAuthority(maxPathLength: maxPathLength) : .notCertificateAuthority
    }
}

extension NitroCertificate.KeyUsage {
    /// Decodes a key usage extension's value.
    ///
    /// - Parameter bytes: The DER of the value.
    /// - Throws: ``NitroCertificate/ValidationError/invalidBitString`` for a BIT STRING with invalid unused bits,
    ///   trailing zero bits, or no bits set, ``NitroCertificate/ValidationError/malformed`` for another type, or a
    ///   `DER.ValidationError` for bytes that aren't DER.
    init(decoding bytes: [UInt8]) throws {
        let (octets, unusedBitCount) = try DER(decoding: bytes).bitString()
        guard let first = octets.first, let last = octets.last, last & (1 << unusedBitCount) != 0 else {
            throw NitroCertificate.ValidationError.invalidBitString
        }
        digitalSignature = first & 0x80 != 0
        keyCertSign = first & 0x04 != 0
    }
}
