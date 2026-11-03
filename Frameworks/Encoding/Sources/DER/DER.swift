/// A value in the Distinguished Encoding Rules of ITU-T X.690.
///
/// Decoding enforces DER's identifier, length, and form rules. Every length is definite and in its shortest form, and
/// every tag number is below 31 in a single identifier octet, other than the universal end-of-contents tag 0.
/// Universal EXTERNAL, EMBEDDED PDV, SEQUENCE, SET, and CHARACTER STRING values are constructed and other universal
/// values are primitive. Constructed values other than empty ones nest at most 16 deep. Decoding doesn't read
/// primitive contents, such as INTEGER or BOOLEAN values, or check the order of SET OF elements.
public struct DER: Hashable, Sendable {
    /// A value's tag.
    public struct Identifier: Hashable, Sendable {
        /// The class of a tag.
        public enum TagClass: UInt8, Hashable, Sendable {
            case universal = 0
            case application = 1
            case contextSpecific = 2
            case `private` = 3
        }

        public let tagNumber: UInt8
        public let tagClass: TagClass

        /// Creates an identifier.
        ///
        /// - Precondition: `number` is below 31.
        /// - Parameters:
        ///   - number: The tag number.
        ///   - tagClass: The class of the tag.
        public init(tagWithNumber number: UInt8, tagClass: TagClass) {
            precondition(number < 31, "The tag number must be below 31.")
            tagNumber = number
            self.tagClass = tagClass
        }
    }

    /// A value's contents.
    public enum Content: Hashable, Sendable {
        /// The bytes of a primitive value.
        case primitive([UInt8])
        /// The values in a constructed value, in order.
        case constructed([DER])
    }

    /// An encoding that isn't DER or falls outside what the decoder supports.
    public enum ValidationError: Error, Equatable {
        case malformed
        case trailingBytes
        /// A tag number of 31 or more, or the universal end-of-contents tag 0.
        case unsupportedTag
        case indefiniteLength
        case nonMinimalLength
        /// A universal value in the form, primitive or constructed, that DER doesn't use for its type.
        case invalidForm
        case nestedTooDeep
    }

    public let identifier: Identifier
    public let content: Content
}

extension DER {
    /// The most octets a long-form length may take.
    ///
    /// A length in more octets that doesn't start with a zero octet is at least 2⁶⁴ bytes, longer than any input.
    fileprivate static let maximumLengthOctetCount = 8

    /// The universal tag numbers of EXTERNAL, EMBEDDED PDV, SEQUENCE, SET, and CHARACTER STRING, the types DER encodes
    /// constructed.
    fileprivate static let constructedUniversalTagNumbers: Set<UInt8> = [8, 11, 16, 17, 29]

    private static let maximumDepth = 16

    /// The value's encoding, which for a decoded value is exactly the bytes it was decoded from.
    public var encoded: [UInt8] {
        let (form, contents): (UInt8, [UInt8]) =
            switch content {
            case .primitive(let bytes): (0, bytes)
            case .constructed(let values): (0x20, values.flatMap(\.encoded))
            }
        var bytes = [identifier.tagClass.rawValue << 6 | form | identifier.tagNumber]
        bytes.appendLength(contents.count)
        bytes.append(contentsOf: contents)
        return bytes
    }

    /// Decodes exactly one value.
    ///
    /// - Parameter bytes: The encoded value, with no trailing bytes.
    /// - Throws: A ``ValidationError`` for an encoding that isn't DER or falls outside what the decoder supports.
    public init(decoding bytes: some Collection<UInt8>) throws {
        var input = ByteReader(Array(bytes), error: ValidationError.malformed)
        try self.init(parsing: &input, depth: 0)
        guard input.isAtEnd else { throw ValidationError.trailingBytes }
    }

    /// Reads one value.
    ///
    /// - Parameters:
    ///   - input: The reader at the value's identifier octet.
    ///   - depth: The number of constructed values that enclose the value.
    /// - Throws: A ``ValidationError`` for an encoding that isn't DER or falls outside what the decoder supports.
    private init(parsing input: inout ByteReader, depth: Int) throws {
        let (identifier, isConstructed) = try input.identifier()
        let length = try input.length()
        let contents = try input.read(count: length)
        guard isConstructed else {
            self.init(identifier: identifier, content: .primitive(Array(contents)))
            return
        }
        guard contents.isEmpty || depth < Self.maximumDepth else { throw ValidationError.nestedTooDeep }
        var reader = ByteReader(Array(contents), error: ValidationError.malformed)
        var values: [DER] = []
        while !reader.isAtEnd {
            values.append(try DER(parsing: &reader, depth: depth + 1))
        }
        self.init(identifier: identifier, content: .constructed(values))
    }
}

extension DER.Identifier {
    public static let boolean = Self(tagWithNumber: 1, tagClass: .universal)
    public static let integer = Self(tagWithNumber: 2, tagClass: .universal)
    public static let bitString = Self(tagWithNumber: 3, tagClass: .universal)
    public static let octetString = Self(tagWithNumber: 4, tagClass: .universal)
    public static let null = Self(tagWithNumber: 5, tagClass: .universal)
    // swift-format-ignore: DontRepeatTypeInStaticProperties
    public static let objectIdentifier = Self(tagWithNumber: 6, tagClass: .universal)
    public static let sequence = Self(tagWithNumber: 16, tagClass: .universal)
    public static let set = Self(tagWithNumber: 17, tagClass: .universal)
}

private extension ByteReader {
    /// Reads a DER identifier octet.
    ///
    /// - Returns: The value's identifier, and whether the value is constructed.
    /// - Throws: ``DER/ValidationError/unsupportedTag`` for the high-tag-number form or the universal end-of-contents
    ///   tag 0, ``DER/ValidationError/invalidForm`` for a universal value in a form DER doesn't use for its type, or
    ///   ``DER/ValidationError/malformed`` for truncated input.
    mutating func identifier() throws -> (identifier: DER.Identifier, isConstructed: Bool) {
        let octet: UInt8 = try integer()
        let number = octet & 0x1f
        guard number != 0x1f else { throw DER.ValidationError.unsupportedTag }
        let identifier = DER.Identifier(tagWithNumber: number, tagClass: .init(identifierOctet: octet))
        let isConstructed = octet & 0x20 != 0
        guard identifier != DER.Identifier(tagWithNumber: 0, tagClass: .universal) else {
            throw DER.ValidationError.unsupportedTag
        }
        guard
            identifier.tagClass != .universal
                || isConstructed == DER.constructedUniversalTagNumbers.contains(identifier.tagNumber)
        else { throw DER.ValidationError.invalidForm }
        return (identifier, isConstructed)
    }

    /// Reads a DER length.
    ///
    /// - Returns: The number of content bytes that follow.
    /// - Throws: ``DER/ValidationError/indefiniteLength`` for the indefinite form,
    ///   ``DER/ValidationError/nonMinimalLength`` for a long form that a shorter form could express, or
    ///   ``DER/ValidationError/malformed`` for truncated input or a long form in more than eight octets.
    mutating func length() throws -> Int {
        let initial: UInt8 = try integer()
        guard initial & 0x80 != 0 else { return Int(initial) }
        guard initial != 0x80 else { throw DER.ValidationError.indefiniteLength }
        let octets = try read(count: Int(initial & 0x7f))
        guard octets.first != 0 else { throw DER.ValidationError.nonMinimalLength }
        guard octets.count <= DER.maximumLengthOctetCount else { throw DER.ValidationError.malformed }
        let length = octets.reduce(0) { $0 << 8 | UInt64($1) }
        guard length >= 0x80 else { throw DER.ValidationError.nonMinimalLength }
        return Int(clamping: length)
    }
}

private extension DER.Identifier.TagClass {
    /// Creates the class that the top two bits of an identifier octet encode.
    ///
    /// - Parameter octet: The identifier octet.
    init(identifierOctet octet: UInt8) {
        self =
            switch octet >> 6 {
            case 0: .universal
            case 1: .application
            case 2: .contextSpecific
            default: .private
            }
    }
}

private extension [UInt8] {
    /// Appends a definite length in its shortest form.
    ///
    /// - Parameter length: The number of content bytes.
    mutating func appendLength(_ length: Int) {
        guard length >= 0x80 else {
            append(UInt8(length))
            return
        }
        let byteCount = (Int.bitWidth - length.leadingZeroBitCount + 7) / 8
        append(0x80 | UInt8(byteCount))
        append(contentsOf: (0..<byteCount).reversed().map { UInt8(truncatingIfNeeded: length >> ($0 * 8)) })
    }
}
