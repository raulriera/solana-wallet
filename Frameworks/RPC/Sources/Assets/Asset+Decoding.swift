import Foundation

extension Asset {
    /// Decodes a DAS asset's identity and the provider's HTTPS copy of its image.
    ///
    /// A malformed file entry is skipped without losing its neighbors. Asset identity remains strictly decoded.
    /// - Parameter decoder: The decoder containing the DAS asset.
    /// - Throws: A decoding error for a malformed identity.
    public init(from decoder: any Decoder) throws {
        let root = try Fields(from: decoder)
        let files = root.object("content")?.objects("files") ?? []
        // Only the provider's HTTPS copy: creator-hosted and off-chain links expose the viewer's IP address.
        let image = files.first { file in
            file.value("mime", as: String.self)?.hasPrefix("image/") == true
                && file.url("cdn_uri")?.scheme?.lowercased() == "https"
        }
        self.init(id: try root.required(String.self, "id"), imageURL: image?.url("cdn_uri"))
    }
}

/// Private DAS field access; provider keys never become shared Codable keys.
private struct Fields: Decodable {
    private let container: KeyedDecodingContainer<Key>

    /// Reads an object without imposing a provider schema on domain values.
    /// - Parameter decoder: The decoder containing the object.
    /// - Throws: A decoding error if the value isn't an object.
    init(from decoder: any Decoder) throws { container = try decoder.container(keyedBy: Key.self) }

    /// Reads a required field with strict type validation.
    /// - Parameters:
    ///   - type: The expected value type.
    ///   - name: The provider's field name.
    /// - Returns: The decoded value.
    /// - Throws: A decoding error for absent or malformed values.
    func required<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
        try container.decode(type, forKey: Key(name))
    }

    /// Reads an optional field, rejecting malformed supplied values.
    /// - Parameters:
    ///   - type: The expected value type.
    ///   - name: The provider's field name.
    /// - Returns: The decoded value, or `nil` for absence or null.
    /// - Throws: A decoding error for a malformed supplied value.
    func optional<T: Decodable>(_ type: T.Type, _ name: String) throws -> T? {
        try container.decodeIfPresent(type, forKey: Key(name))
    }

    /// Reads an optional display field independently of its neighbors.
    /// - Parameters:
    ///   - name: The provider's field name.
    ///   - type: The expected value type.
    /// - Returns: The decoded value, or `nil` if absent or malformed.
    func value<T: Decodable>(_ name: String, as type: T.Type = T.self) -> T? { try? optional(type, name) }

    /// Reads an optional nested object.
    /// - Parameter name: The provider's field name.
    /// - Returns: The object, or `nil` if absent or malformed.
    func object(_ name: String) -> Fields? { value(name) }

    /// Reads valid objects from an optional list without losing healthy neighbors.
    /// - Parameter name: The provider's list name.
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

    /// Reads a nonempty absolute resource URL, including decentralized URI schemes.
    /// - Parameter name: The provider's URL field.
    /// - Returns: The URL, or `nil` if empty, relative, or malformed.
    func url(_ name: String) -> URL? {
        guard let text = value(name, as: String.self), !text.isEmpty,
              let url = URL(string: text), url.scheme != nil else { return nil }
        return url
    }

    /// An internal key for the provider's JSON field names.
    private struct Key: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        /// Creates a key from a provider field name.
        /// - Parameter name: The field name.
        init(_ name: String) { stringValue = name }
        /// Creates a key from a coding string.
        /// - Parameter stringValue: The field name.
        init?(stringValue: String) { self.init(stringValue) }
        /// Rejects integer keys because DAS objects use string keys.
        /// - Parameter intValue: The unsupported integer key.
        init?(intValue: Int) { return nil }
    }
}
