/// A transaction error as a named variant with optional details.
public struct TransactionError: Error, Codable, Sendable, Equatable {
    /// The variant name, such as `BlockhashNotFound` or `InstructionError`.
    public let name: String

    /// The variant's associated data, or `nil` for a variant without data.
    public let details: Detail?

    /// Creates a transaction error.
    ///
    /// - Parameters:
    ///   - name: The variant name.
    ///   - details: The associated data, or `nil` for a variant without data.
    public init(name: String, details: Detail?) {
        self.name = name
        self.details = details
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let name = try? container.decode(String.self) {
            self.init(name: name, details: nil)
            return
        }
        let variants = try container.decode([String: Detail].self)
        guard variants.count == 1, let variant = variants.first else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected one transaction error variant.")
        }
        self.init(name: variant.key, details: variant.value)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        if let details {
            try container.encode([name: details])
        } else {
            try container.encode(name)
        }
    }

    /// An associated value in a transaction or instruction error.
    public indirect enum Detail: Codable, Sendable, Equatable {
        /// An error name or explanatory string.
        case string(String)
        /// An instruction index, account index, or program-specific error code.
        case integer(UInt64)
        /// Ordered values, such as an instruction index followed by its failure.
        case array([Detail])
        /// Named values, such as a custom program error code or account index.
        case object([String: Detail])

        public init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let string = try? container.decode(String.self) {
                self = .string(string)
            } else if let integer = try? container.decode(UInt64.self) {
                self = .integer(integer)
            } else if let array = try? container.decode([Detail].self) {
                self = .array(array)
            } else {
                self = .object(try container.decode([String: Detail].self))
            }
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .string(let string): try container.encode(string)
            case .integer(let integer): try container.encode(integer)
            case .array(let array): try container.encode(array)
            case .object(let object): try container.encode(object)
            }
        }
    }
}
