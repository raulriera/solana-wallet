import Foundation

/// A JSON value from a fixture, compared by structure so key order and number formatting don't
/// matter.
indirect enum JSONValue: Codable, Sendable, Equatable {
    /// `null`.
    case null
    /// A Boolean.
    case bool(Bool)
    /// A number.
    case number(Double)
    /// A string.
    case string(String)
    /// An array.
    case array([JSONValue])
    /// An object.
    case object([String: JSONValue])

    /// Decodes any JSON value.
    ///
    /// - Parameter decoder: The decoder that supplies the value.
    /// - Throws: A decoding error if the value isn't JSON.
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    /// Encodes the value.
    ///
    /// - Parameter encoder: The encoder that receives the value.
    /// - Throws: An encoding error.
    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    /// Decodes JSON data into a value.
    ///
    /// - Parameter data: The JSON data.
    /// - Returns: The value.
    /// - Throws: A decoding error if the data isn't JSON.
    static func decode(_ data: Data) throws -> Self {
        try JSONDecoder().decode(Self.self, from: data)
    }

    /// The value's JSON data.
    ///
    /// - Throws: An encoding error.
    var data: Data {
        get throws { try JSONEncoder().encode(self) }
    }
}
