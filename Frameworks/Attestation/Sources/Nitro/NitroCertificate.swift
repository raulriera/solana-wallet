import Algorithms
import Encoding
import Foundation

/// An X.509 v3 certificate, RFC 5280, decoded from DER.
struct NitroCertificate: Sendable {
    /// An error that rejects bytes as an X.509 v3 certificate.
    enum ValidationError: Error, Equatable {
        /// Fields that are missing, extra, out of order, or of other types than RFC 5280's.
        case malformed
        /// A version other than v3.
        case unsupportedVersion
        /// An INTEGER that is empty, isn't in its shortest form, or falls outside its field's range, such as a serial
        /// number that isn't positive or is longer than 20 octets.
        case invalidInteger
        /// A BOOLEAN other than TRUE in a field whose default is FALSE.
        case invalidBoolean
        /// A BIT STRING with unused bits that DER or its field doesn't allow, or a key usage with no bits set.
        case invalidBitString
        /// An OBJECT IDENTIFIER that is empty or has a subidentifier that isn't in its shortest form or doesn't end.
        case invalidObjectIdentifier
        /// A time other than a UTCTime through 2049 or a GeneralizedTime from 2050, in whole seconds with `Z`, that
        /// names a moment of the Gregorian calendar.
        case invalidTime
        /// Two extensions with the same OID.
        case duplicateExtension
    }

    private static let version = DER.Identifier(tagWithNumber: 0, tagClass: .contextSpecific)

    private static let extensionList = DER.Identifier(tagWithNumber: 3, tagClass: .contextSpecific)

    private static let utcTime = DER.Identifier(tagWithNumber: 23, tagClass: .universal)

    private static let generalizedTime = DER.Identifier(tagWithNumber: 24, tagClass: .universal)

    /// The Gregorian calendar in UTC, which certificate times use.
    private static let gregorianUTC: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }()

    private static let timeComponents: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]

    /// The DER of the signed part, `TBSCertificate`.
    let tbsCertificateBytes: [UInt8]

    /// The DER of the signature algorithm identifier in the signed part.
    let tbsSignatureAlgorithm: [UInt8]

    /// The DER of the issuer's name.
    let issuer: [UInt8]

    let notValidBefore: Date

    let notValidAfter: Date

    /// The DER of the subject's name.
    let subject: [UInt8]

    /// The DER of the subject key's algorithm identifier.
    let publicKeyAlgorithm: [UInt8]

    /// The subject key's bits.
    let publicKey: [UInt8]

    let extensions: [Extension]

    /// The basic constraints extension's value, or `nil` for a certificate without the extension.
    let basicConstraints: BasicConstraints?

    /// The key usage extension's value, or `nil` for a certificate without the extension.
    let keyUsage: KeyUsage?

    /// The DER of the signature algorithm identifier outside the signed part.
    let signatureAlgorithm: [UInt8]

    /// The signature's bits.
    let signature: [UInt8]

    /// Decodes a certificate.
    ///
    /// - Parameter bytes: The certificate's DER, with no trailing bytes.
    /// - Throws: A ``ValidationError`` for a certificate that breaks a DER or RFC 5280 rule the decoder checks, or a
    ///   `DER.ValidationError` for bytes, including a basic constraints or key usage value, that aren't DER.
    init(decoding bytes: [UInt8]) throws {
        var certificate = try DER(decoding: bytes).fields()
        let tbsCertificate = try certificate.next()
        signatureAlgorithm = try Self.algorithmIdentifier(certificate.next())
        signature = try certificate.next().octetAlignedBitString()
        try certificate.finish()

        var fields = try tbsCertificate.fields()
        guard let version = try fields.next(explicitlyTagged: Self.version),
            try version.nonNegativeInteger() == [2]
        else { throw ValidationError.unsupportedVersion }
        guard try (1...20).contains(fields.next().nonNegativeInteger().count) else {
            throw ValidationError.invalidInteger
        }
        tbsSignatureAlgorithm = try Self.algorithmIdentifier(fields.next())
        issuer = try Self.name(fields.next())
        var validity = try fields.next().fields()
        notValidBefore = try Self.time(validity.next())
        notValidAfter = try Self.time(validity.next())
        try validity.finish()
        subject = try Self.name(fields.next())
        var publicKeyInfo = try fields.next().fields()
        publicKeyAlgorithm = try Self.algorithmIdentifier(publicKeyInfo.next())
        publicKey = try publicKeyInfo.next().octetAlignedBitString()
        try publicKeyInfo.finish()
        extensions = try fields.next(explicitlyTagged: Self.extensionList).map(Self.extensions(in:)) ?? []
        try fields.finish()

        basicConstraints = try extensions.first { $0.oid == Extension.basicConstraintsOID }
            .map { try BasicConstraints(decoding: $0.value) }
        keyUsage = try extensions.first { $0.oid == Extension.keyUsageOID }.map { try KeyUsage(decoding: $0.value) }
        tbsCertificateBytes = tbsCertificate.encoded
    }

    /// Checks an RFC 5280 `AlgorithmIdentifier`, an OID with optional parameters.
    ///
    /// - Parameter value: The value to check.
    /// - Returns: The value's DER.
    /// - Throws: A ``ValidationError`` for another structure or an invalid OID.
    private static func algorithmIdentifier(_ value: DER) throws -> [UInt8] {
        let fields = try value.values()
        guard (1...2).contains(fields.count) else { throw ValidationError.malformed }
        _ = try fields[0].objectIdentifier()
        return value.encoded
    }

    /// Checks an RFC 5280 `Name`: one or more relative names, each a DER-ordered set of one or more attributes
    /// of a type and a value.
    ///
    /// - Parameter value: The value to check.
    /// - Returns: The value's DER.
    /// - Throws: A ``ValidationError`` for another structure or an invalid attribute type.
    private static func name(_ value: DER) throws -> [UInt8] {
        let relativeNames = try value.values()
        guard !relativeNames.isEmpty else { throw ValidationError.malformed }
        for relativeName in relativeNames {
            let attributes = try relativeName.values(.set)
            guard !attributes.isEmpty,
                zip(attributes, attributes.dropFirst()).allSatisfy({ !$1.encoded.lexicographicallyPrecedes($0.encoded) })
            else { throw ValidationError.malformed }
            for attribute in attributes {
                var fields = try attribute.fields()
                _ = try fields.next().objectIdentifier()
                _ = try fields.next()
                try fields.finish()
            }
        }
        return value.encoded
    }

    /// Reads an RFC 5280 `Time`: a UTCTime, `YYMMDDHHMMSSZ`, for years 1950 through 2049, or a GeneralizedTime,
    /// `YYYYMMDDHHMMSSZ`, for years from 2050.
    ///
    /// - Parameter value: The value to read.
    /// - Returns: The moment.
    /// - Throws: ``ValidationError/malformed`` for another type, or ``ValidationError/invalidTime`` for other
    ///   characters, a GeneralizedTime before 2050, or fields that don't name a moment of the Gregorian calendar.
    private static func time(_ value: DER) throws -> Date {
        let yearDigitCount =
            switch value.identifier {
            case Self.utcTime: 2
            case Self.generalizedTime: 4
            default: throw ValidationError.malformed
            }
        guard case .primitive(let bytes) = value.content, bytes.count == yearDigitCount + 11,
            bytes.last == UInt8(ascii: "Z")
        else { throw ValidationError.invalidTime }
        let digits = bytes.dropLast().map { Int($0) - Int(UInt8(ascii: "0")) }
        guard digits.allSatisfy((0...9).contains) else { throw ValidationError.invalidTime }
        let year = digits.prefix(yearDigitCount).reduce(0) { $0 * 10 + $1 }
        let fields = digits.dropFirst(yearDigitCount).chunks(ofCount: 2).map { pair in pair.reduce(0) { $0 * 10 + $1 } }
        guard yearDigitCount == 2 || year >= 2050 else { throw ValidationError.invalidTime }
        let components = DateComponents(
            year: yearDigitCount == 4 ? year : year + (year < 50 ? 2000 : 1900),
            month: fields[0],
            day: fields[1],
            hour: fields[2],
            minute: fields[3],
            second: fields[4]
        )
        guard let date = gregorianUTC.date(from: components),
            gregorianUTC.dateComponents(timeComponents, from: date) == components
        else { throw ValidationError.invalidTime }
        return date
    }

    /// Reads the extension list, a sequence of one or more extensions with distinct OIDs.
    ///
    /// - Parameter list: The value inside the signed part's extension tag.
    /// - Returns: The extensions, in order.
    /// - Throws: A ``ValidationError`` for an empty list, another structure, or two extensions with one OID.
    private static func extensions(in list: DER) throws -> [Extension] {
        let extensions = try list.values().map(Extension.init(decoding:))
        guard !extensions.isEmpty else { throw ValidationError.malformed }
        guard Set(extensions.map(\.oid)).count == extensions.count else { throw ValidationError.duplicateExtension }
        return extensions
    }
}
