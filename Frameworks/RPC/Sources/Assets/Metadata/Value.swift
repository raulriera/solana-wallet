public import Foundation

extension Metadata {
    /// A metadata value that preserves JSON structure and decimal precision.
    public indirect enum Value: Codable, Sendable, Equatable {
        /// A textual value.
        case string(String)
        /// A decimal or integer value without binary floating-point conversion.
        case number(Decimal)
        /// A boolean value.
        case bool(Bool)
        /// An explicit null value.
        case null
        /// An ordered list of values.
        case array([Value])
        /// Named values.
        case object([String: Value])

        /// Decodes a metadata value while retaining its JSON type.
        /// - Parameter decoder: The decoder containing the value.
        /// - Throws: A decoding error for unsupported values.
        public init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if container.decodeNil() { self = .null }
            else if let value = try? container.decode(Bool.self) { self = .bool(value) }
            else if let value = try? container.decode(String.self) { self = .string(value) }
            else if let value = try? container.decode(Decimal.self) { self = .number(value) }
            else if let value = try? container.decode([Value].self) { self = .array(value) }
            else { self = .object(try container.decode([String: Value].self)) }
        }

        /// Encodes the value using its original JSON type.
        /// - Parameter encoder: The encoder receiving the value.
        /// - Throws: An encoding error if the value can't be represented.
        public func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .string(let value): try container.encode(value)
            case .number(let value): try container.encode(value)
            case .bool(let value): try container.encode(value)
            case .null: try container.encodeNil()
            case .array(let value): try container.encode(value)
            case .object(let value): try container.encode(value)
            }
        }
    }
}
