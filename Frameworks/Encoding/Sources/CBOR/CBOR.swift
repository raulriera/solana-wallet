/// A data item in a strict subset of CBOR, RFC 8949.
///
/// The subset has no floats, no indefinite-length strings, and no simple values other than `false`, `true`, and
/// `null`. Integers are at most 2⁵³ − 1 in magnitude, arrays and maps other than empty definite-length ones nest
/// at most 16 deep, and map keys are unique integers or text strings.
public enum CBOR: Hashable, Sendable {
    case integer(Int64)
    case bytes([UInt8])
    case text(String)
    case array([CBOR])
    case map([Key: CBOR])
    case boolean(Bool)
    case null

    /// A map key.
    public enum Key: Hashable, Sendable {
        case integer(Int64)
        case text(String)

        /// Reads a map key.
        ///
        /// - Parameters:
        ///   - input: The reader at the key's first byte.
        ///   - depth: The number of containers that enclose the key.
        /// - Throws: ``ValidationError/invalidKey`` for a key other than an integer or a text string, or another
        ///   ``ValidationError`` for invalid CBOR or an encoding outside the subset.
        fileprivate init(parsing input: inout ByteReader, depth: Int) throws {
            switch try CBOR(parsing: &input, depth: depth) {
            case .integer(let value): self = .integer(value)
            case .text(let value): self = .text(value)
            default: throw ValidationError.invalidKey
            }
        }
    }

    /// An encoding that isn't valid CBOR or falls outside the subset.
    public enum ValidationError: Error, Equatable {
        case malformed
        case trailingBytes
        case unsupportedTag
        case float
        case unsupportedSimpleValue
        case integerOutOfRange
        case indefiniteString
        case invalidText
        case nestedTooDeep
        case invalidKey
        case duplicateKey
    }

    private static let maximumMagnitude: UInt64 = (1 << 53) - 1

    private static let maximumDepth = 16

    /// Decodes exactly one data item.
    ///
    /// - Parameters:
    ///   - bytes: The encoded item, with no trailing bytes.
    ///   - tag: A tag that may precede the item once, or `nil` to reject every tag.
    /// - Throws: A ``ValidationError`` for invalid CBOR or an encoding outside the subset.
    public init(decoding bytes: some Collection<UInt8>, allowingLeadingTag tag: UInt64? = nil) throws {
        var input = ByteReader(Array(bytes), error: ValidationError.malformed)
        try self.init(parsing: &input, depth: 0, allowingTag: tag)
        guard input.isAtEnd else { throw ValidationError.trailingBytes }
    }

    /// Reads one data item.
    ///
    /// - Parameters:
    ///   - input: The reader at the item's first byte.
    ///   - depth: The number of containers that enclose the item.
    ///   - tag: A tag that may precede the item, or `nil` to reject every tag.
    /// - Throws: A ``ValidationError`` for invalid CBOR or an encoding outside the subset.
    private init(parsing input: inout ByteReader, depth: Int, allowingTag tag: UInt64? = nil) throws {
        let (majorType, additional, argument) = try input.header()
        switch majorType {
        case 0:
            guard let argument else { throw ValidationError.malformed }
            guard argument <= Self.maximumMagnitude else { throw ValidationError.integerOutOfRange }
            self = .integer(Int64(argument))
        case 1:
            guard let argument else { throw ValidationError.malformed }
            guard argument < Self.maximumMagnitude else { throw ValidationError.integerOutOfRange }
            self = .integer(-1 - Int64(argument))
        case 2:
            guard let argument else { throw ValidationError.indefiniteString }
            self = .bytes(Array(try input.read(count: Int(clamping: argument))))
        case 3:
            guard let argument else { throw ValidationError.indefiniteString }
            guard let text = String(validating: try input.read(count: Int(clamping: argument)), as: UTF8.self) else {
                throw ValidationError.invalidText
            }
            self = .text(text)
        case 4...5 where argument != 0 && depth >= Self.maximumDepth:
            throw ValidationError.nestedTooDeep
        case 4:
            var items: [CBOR] = []
            while try input.hasNext(of: argument, count: items.count) {
                items.append(try CBOR(parsing: &input, depth: depth + 1))
            }
            self = .array(items)
        case 5:
            var entries: [Key: CBOR] = [:]
            while try input.hasNext(of: argument, count: entries.count) {
                let key = try Key(parsing: &input, depth: depth + 1)
                let value = try CBOR(parsing: &input, depth: depth + 1)
                guard entries.updateValue(value, forKey: key) == nil else { throw ValidationError.duplicateKey }
            }
            self = .map(entries)
        case 6:
            guard let tag, argument == tag else { throw ValidationError.unsupportedTag }
            self = try CBOR(parsing: &input, depth: depth)
        default:
            switch additional {
            case 20: self = .boolean(false)
            case 21: self = .boolean(true)
            case 22: self = .null
            case 25, 26, 27: throw ValidationError.float
            case 31: throw ValidationError.malformed
            default: throw ValidationError.unsupportedSimpleValue
            }
        }
    }
}

private extension ByteReader {
    /// Reads the initial byte of a CBOR data item and the argument that follows it.
    ///
    /// - Returns: The major type, the additional information, and the argument, or a `nil` argument for an
    ///   indefinite length.
    /// - Throws: ``CBOR/ValidationError/malformed`` for truncated input or reserved additional information.
    mutating func header() throws -> (majorType: UInt8, additional: UInt8, argument: UInt64?) {
        let initial: UInt8 = try integer()
        let additional = initial & 0x1f
        let argument: UInt64? =
            switch additional {
            case 0..<24: UInt64(additional)
            case 24...27: try read(count: 1 << (additional - 24)).reduce(0) { $0 << 8 | UInt64($1) }
            case 31: nil
            default: throw CBOR.ValidationError.malformed
            }
        return (initial >> 5, additional, argument)
    }

    /// Reports whether a CBOR container has another element, and reads the break that ends an indefinite-length
    /// container.
    ///
    /// - Parameters:
    ///   - argument: The container's length, or `nil` for an indefinite length.
    ///   - count: The number of elements read so far.
    /// - Returns: `true` when another element follows.
    /// - Throws: ``CBOR/ValidationError/malformed`` for truncated input.
    mutating func hasNext(of argument: UInt64?, count: Int) throws -> Bool {
        if let argument { return UInt64(count) < argument }
        guard nextByte == 0xff else { return true }
        _ = try read(count: 1)
        return false
    }
}
