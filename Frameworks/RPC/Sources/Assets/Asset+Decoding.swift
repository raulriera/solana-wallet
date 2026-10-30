import Foundation

extension Asset {
    public init(from decoder: any Decoder) throws {
        let root = try Fields(from: decoder)
        let files = root.object("content")?.objects("files") ?? []
        let image = files.first { file in
            file.value("mime", as: String.self)?.hasPrefix("image/") == true
                && file.url("cdn_uri")?.scheme?.lowercased() == "https"
        }
        self.init(id: try root.required(String.self, "id"), imageURL: image?.url("cdn_uri"))
    }
}

/// A DAS JSON object whose fields are read by name.
private struct Fields: Decodable {
    private let container: KeyedDecodingContainer<Key>

    init(from decoder: any Decoder) throws { container = try decoder.container(keyedBy: Key.self) }

    /// Reads a required field.
    ///
    /// - Parameters:
    ///   - type: The expected value type.
    ///   - name: The field name.
    /// - Returns: The decoded value.
    /// - Throws: A decoding error for an absent or malformed value.
    func required<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
        try container.decode(type, forKey: Key(name))
    }

    /// Reads an optional field.
    ///
    /// - Parameters:
    ///   - type: The expected value type.
    ///   - name: The field name.
    /// - Returns: The decoded value, or `nil` if absent or null.
    /// - Throws: A decoding error for a malformed value.
    func optional<T: Decodable>(_ type: T.Type, _ name: String) throws -> T? {
        try container.decodeIfPresent(type, forKey: Key(name))
    }

    /// Reads an optional field, ignoring a malformed value.
    ///
    /// - Parameters:
    ///   - name: The field name.
    ///   - type: The expected value type.
    /// - Returns: The decoded value, or `nil` if absent or malformed.
    func value<T: Decodable>(_ name: String, as type: T.Type = T.self) -> T? { try? optional(type, name) }

    /// Reads an optional nested object.
    ///
    /// - Parameter name: The field name.
    /// - Returns: The object, or `nil` if absent or malformed.
    func object(_ name: String) -> Fields? { value(name) }

    /// Reads the valid objects in an optional list.
    ///
    /// - Parameter name: The field name.
    /// - Returns: The decoded objects, or `nil` if the field isn't a list.
    func objects(_ name: String) -> [Fields]? {
        guard var list = try? container.nestedUnkeyedContainer(forKey: Key(name)) else { return nil }
        var objects: [Fields] = []
        while !list.isAtEnd {
            guard let decoder = try? list.superDecoder() else { break }
            if let object = try? Fields(from: decoder) { objects.append(object) }
        }
        return objects
    }

    /// Reads a nonempty absolute URL.
    ///
    /// - Parameter name: The field name.
    /// - Returns: The URL, or `nil` if empty, relative, or malformed.
    func url(_ name: String) -> URL? {
        guard let text = value(name, as: String.self), !text.isEmpty,
              let url = URL(string: text), url.scheme != nil else { return nil }
        return url
    }

    /// A coding key for a field name.
    private struct Key: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        /// Creates a key from a field name.
        ///
        /// - Parameter name: The field name.
        init(_ name: String) { stringValue = name }
        init?(stringValue: String) { self.init(stringValue) }
        init?(intValue: Int) { return nil }
    }
}
