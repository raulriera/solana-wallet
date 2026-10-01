/// A transaction failure reported as a named variant with optional structured details.
public struct TransactionError: Error, Decodable, Sendable, Equatable {
    /// The variant name reported by the node, such as `BlockhashNotFound` or `InstructionError`.
    public let name: String

    /// The variant's associated data, or `nil` for a failure encoded as a name alone.
    public let details: Detail?

    /// Creates a transaction failure with its reported variant and details.
    ///
    /// - Parameters:
    ///   - name: The error variant reported by the node.
    ///   - details: The associated data, or `nil` for a variant without data.
    public init(name: String, details: Detail?) {
        self.name = name
        self.details = details
    }

    /// Decodes a simple variant name or an object containing one variant and its details.
    ///
    /// - Parameter decoder: The decoder containing the transaction failure.
    /// - Throws: A decoding error if the value isn't a name or a single variant object.
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

    /// Associated values in a transaction or instruction error.
    public indirect enum Detail: Decodable, Sendable, Equatable {
        /// An error name or explanatory string.
        case string(String)
        /// An instruction index, account index, or program-specific error code.
        case integer(UInt64)
        /// Ordered values, such as an instruction index followed by its failure.
        case array([Detail])
        /// Named values, such as a custom program error code or account index.
        case object([String: Detail])

        /// Decodes associated error data while retaining its structure and exact integers.
        ///
        /// - Parameter decoder: The decoder containing the associated data.
        /// - Throws: A decoding error if the value isn't part of the transaction-error format.
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
    }
}
