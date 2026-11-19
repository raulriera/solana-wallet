public import Foundation

/// A coding that keeps a value as JSON beside the version of its format.
public struct VersionedJSONCoding<Value: Codable & Equatable & Sendable>: ValueCoding {
    let version: Int
    let outdated: Value

    /// Creates a coding that keeps values as JSON in one version of a format.
    ///
    /// - Parameters:
    ///   - version: The version of the format that the coding writes and reads.
    ///   - outdated: The value that bytes of another version decode to.
    public init(version: Int, outdated: Value) {
        self.version = version
        self.outdated = outdated
    }

    public func encode(_ value: Value) throws -> Data {
        try JSONEncoder().encode(Envelope(version: version, value: value))
    }

    public func decode(_ data: Data) -> Value? {
        let decoder = JSONDecoder()
        guard let saved = try? decoder.decode(Version.self, from: data) else { return nil }
        guard saved.version == version else { return outdated }
        return (try? decoder.decode(Envelope.self, from: data))?.value
    }

    /// A value's kept contents, with the version of its format.
    private struct Envelope: Codable {
        let version: Int
        let value: Value
    }

    /// The version of the format of kept bytes.
    private struct Version: Decodable {
        let version: Int
    }
}

extension ValueCoding {
    /// Returns a coding that keeps a value of the given type as JSON beside the version of its format.
    ///
    /// - Parameters:
    ///   - type: The type of the saved value.
    ///   - version: The version of the format that the coding writes and reads.
    ///   - outdated: The value that bytes of another version decode to.
    /// - Returns: A coding that keeps the value as versioned JSON.
    public static func json<Saved>(_ type: Saved.Type, version: Int, outdated: Saved) -> Self
    where Self == VersionedJSONCoding<Saved> {
        VersionedJSONCoding(version: version, outdated: outdated)
    }
}
