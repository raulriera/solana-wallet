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

    /// Decodes exactly one data item.
    ///
    /// - Parameters:
    ///   - bytes: The encoded item, with no trailing bytes.
    ///   - tag: A tag that may precede the item once, or `nil` to reject every tag.
    /// - Throws: A ``ValidationError`` for invalid CBOR or an encoding outside the subset.
    public init(decoding bytes: some Collection<UInt8>, allowingLeadingTag tag: UInt64? = nil) throws {
        var reader = Reader(bytes: Array(bytes))
        self = try reader.item(depth: 0, allowingTag: tag)
        guard reader.isAtEnd else { throw ValidationError.trailingBytes }
    }

    /// A cursor that reads data items from encoded bytes.
    private struct Reader {
        private static let maximumMagnitude: UInt64 = (1 << 53) - 1

        private static let maximumDepth = 16

        let bytes: [UInt8]
        var offset = 0

        var isAtEnd: Bool { offset == bytes.count }

        var nextByte: UInt8? { isAtEnd ? nil : bytes[offset] }

        /// Reads one data item.
        ///
        /// - Parameters:
        ///   - depth: The number of containers that enclose the item.
        ///   - tag: A tag that may precede the item, or `nil` to reject every tag.
        /// - Returns: The item.
        /// - Throws: A ``ValidationError`` for invalid CBOR or an encoding outside the subset.
        mutating func item(depth: Int, allowingTag tag: UInt64? = nil) throws -> CBOR {
            let (majorType, additional, argument) = try header()
            switch majorType {
            case 0:
                guard let argument else { throw ValidationError.malformed }
                guard argument <= Self.maximumMagnitude else { throw ValidationError.integerOutOfRange }
                return .integer(Int64(argument))
            case 1:
                guard let argument else { throw ValidationError.malformed }
                guard argument < Self.maximumMagnitude else { throw ValidationError.integerOutOfRange }
                return .integer(-1 - Int64(argument))
            case 2:
                guard let argument else { throw ValidationError.indefiniteString }
                return .bytes(Array(try take(argument)))
            case 3:
                guard let argument else { throw ValidationError.indefiniteString }
                guard let text = String(validating: try take(argument), as: UTF8.self) else {
                    throw ValidationError.invalidText
                }
                return .text(text)
            case 4...5 where argument != 0 && depth >= Self.maximumDepth:
                throw ValidationError.nestedTooDeep
            case 4:
                var items: [CBOR] = []
                while try hasNext(of: argument, count: items.count) {
                    items.append(try item(depth: depth + 1))
                }
                return .array(items)
            case 5:
                var entries: [Key: CBOR] = [:]
                while try hasNext(of: argument, count: entries.count) {
                    let key = try mapKey(depth: depth + 1)
                    let value = try item(depth: depth + 1)
                    guard entries.updateValue(value, forKey: key) == nil else { throw ValidationError.duplicateKey }
                }
                return .map(entries)
            case 6:
                guard let tag, argument == tag else { throw ValidationError.unsupportedTag }
                return try item(depth: depth)
            default:
                switch additional {
                case 20: return .boolean(false)
                case 21: return .boolean(true)
                case 22: return .null
                case 25, 26, 27: throw ValidationError.float
                case 31: throw ValidationError.malformed
                default: throw ValidationError.unsupportedSimpleValue
                }
            }
        }

        /// Reads the initial byte of a data item and the argument that follows it.
        ///
        /// - Returns: The major type, the additional information, and the argument, or a `nil` argument for an
        ///   indefinite length.
        /// - Throws: ``ValidationError/malformed`` for truncated input or reserved additional information.
        private mutating func header() throws -> (majorType: UInt8, additional: UInt8, argument: UInt64?) {
            guard let initial = nextByte else { throw ValidationError.malformed }
            offset += 1
            let additional = initial & 0x1f
            let argument: UInt64? =
                switch additional {
                case 0..<24: UInt64(additional)
                case 24...27: try take(1 << (additional - 24)).reduce(0) { $0 << 8 | UInt64($1) }
                case 31: nil
                default: throw ValidationError.malformed
                }
            return (initial >> 5, additional, argument)
        }

        /// Reads a map key.
        ///
        /// - Parameter depth: The number of containers that enclose the key.
        /// - Returns: The key.
        /// - Throws: ``ValidationError/invalidKey`` for a key other than an integer or a text string, or another
        ///   ``ValidationError`` for invalid CBOR or an encoding outside the subset.
        private mutating func mapKey(depth: Int) throws -> Key {
            switch try item(depth: depth) {
            case .integer(let value): .integer(value)
            case .text(let value): .text(value)
            default: throw ValidationError.invalidKey
            }
        }

        /// Reports whether a container has another element, and reads the break that ends an indefinite-length
        /// container.
        ///
        /// - Parameters:
        ///   - argument: The container's length, or `nil` for an indefinite length.
        ///   - count: The number of elements read so far.
        /// - Returns: `true` when another element follows.
        /// - Throws: ``ValidationError/malformed`` for truncated input.
        private mutating func hasNext(of argument: UInt64?, count: Int) throws -> Bool {
            if let argument { return UInt64(count) < argument }
            guard let next = nextByte else { throw ValidationError.malformed }
            guard next == 0xff else { return true }
            offset += 1
            return false
        }

        /// Reads a number of bytes.
        ///
        /// - Parameter count: The number of bytes to read.
        /// - Returns: The bytes.
        /// - Throws: ``ValidationError/malformed`` when fewer bytes remain.
        private mutating func take(_ count: some BinaryInteger) throws -> ArraySlice<UInt8> {
            guard count <= bytes.count - offset else { throw ValidationError.malformed }
            let end = offset + Int(count)
            defer { offset = end }
            return bytes[offset..<end]
        }
    }
}
