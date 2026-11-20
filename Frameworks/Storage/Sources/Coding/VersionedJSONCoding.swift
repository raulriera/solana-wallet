public import Foundation

/// A coding that keeps a value as JSON beside the version of its format.
///
/// Bytes of the coding's version decode to their value. Bytes of an earlier version go through migration. Bytes
/// that can't be used, which are those of a later version, without a version, or with damaged contents, decode to
/// the outdated value, so the next save replaces them.
public struct VersionedJSONCoding<Value: Codable & Equatable & Sendable>: ValueCoding {
    let version: Int
    let outdated: Value

    /// Creates a coding that keeps values as JSON in one version of a format.
    ///
    /// - Parameters:
    ///   - version: The version of the format that the coding writes and reads.
    ///   - outdated: The value that bytes decode to when they can't be used or migrated.
    public init(version: Int, outdated: Value) {
        self.version = version
        self.outdated = outdated
    }

    public func encode(_ value: Value) throws -> Data {
        try JSONEncoder().encode(Envelope(version: version, value: value))
    }

    public func decode(_ data: Data) -> Value? {
        let decoder = JSONDecoder()
        guard let kept = try? decoder.decode(Version.self, from: data) else { return outdated }
        if kept.version == version { return (try? decoder.decode(Envelope.self, from: data))?.value ?? outdated }
        if kept.version < version { return migrated(data, from: kept.version) ?? outdated }
        return outdated
    }

    /// Returns the value of bytes of an earlier version, migrated to this version.
    ///
    /// - Parameters:
    ///   - data: The bytes of the earlier version.
    ///   - earlier: The version of the bytes.
    /// - Returns: The migrated value, or `nil` when no migration reads that version.
    private func migrated(_ data: Data, from earlier: Int) -> Value? {
        nil
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
    ///   - outdated: The value that bytes decode to when they can't be used or migrated.
    /// - Returns: A coding that keeps the value as versioned JSON.
    public static func json<Saved>(_ type: Saved.Type, version: Int, outdated: Saved) -> Self
    where Self == VersionedJSONCoding<Saved> {
        VersionedJSONCoding(version: version, outdated: outdated)
    }
}
