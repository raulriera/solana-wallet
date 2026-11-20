public import Foundation

/// A coding that keeps a value as JSON beside the version of its format.
///
/// Bytes of the coding's version decode to their value. Bytes of an earlier version, or without a version, which
/// count as version 0, go to the migration. Every other case can't be used: a later version, a damaged value, or
/// an earlier version that the migration doesn't read.
public struct VersionedJSONCoding<Value: Codable & Equatable & Sendable>: ValueCoding {
    /// What bytes that can't be used decode to.
    public enum Unusable: Sendable {
        /// The bytes decode to a value, so the next save replaces them.
        case replaced(with: Value)
        /// The bytes decode to nothing, so the store that reads them reports an error and keeps them.
        case unreadable
    }

    /// Returns the value of bytes of an earlier version, given the bytes and their version, or `nil` when it
    /// doesn't read that version.
    public typealias Migration = @Sendable (Data, Int) -> Value?

    let version: Int
    let unusable: Unusable
    let migration: Migration

    /// Creates a coding that keeps values as JSON in one version of a format.
    ///
    /// - Parameters:
    ///   - version: The version of the format that the coding writes and reads, starting at 1.
    ///   - unusable: What bytes that can't be used decode to.
    ///   - migration: Reads bytes of earlier versions.
    public init(version: Int, unusable: Unusable, migration: @escaping Migration = { _, _ in nil }) {
        self.version = version
        self.unusable = unusable
        self.migration = migration
    }

    public func encode(_ value: Value) throws -> Data {
        try JSONEncoder().encode(Envelope(version: version, value: value))
    }

    public func decode(_ data: Data) -> Value? {
        let decoder = JSONDecoder()
        if let kept = try? decoder.decode(Envelope.self, from: data), kept.version == version { return kept.value }
        let found = (try? decoder.decode(Version.self, from: data))?.version ?? 0
        if found < version, let migrated = migration(data, found) { return migrated }
        switch unusable {
        case .replaced(let value): return value
        case .unreadable: return nil
        }
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
    ///   - version: The version of the format that the coding writes and reads, starting at 1.
    ///   - unusable: What bytes that can't be used decode to.
    ///   - migration: Reads bytes of earlier versions.
    /// - Returns: A coding that keeps the value as versioned JSON.
    public static func json<Saved>(
        _ type: Saved.Type, version: Int, unusable: VersionedJSONCoding<Saved>.Unusable,
        migration: @escaping VersionedJSONCoding<Saved>.Migration = { _, _ in nil }
    ) -> Self where Self == VersionedJSONCoding<Saved> {
        VersionedJSONCoding(version: version, unusable: unusable, migration: migration)
    }
}
