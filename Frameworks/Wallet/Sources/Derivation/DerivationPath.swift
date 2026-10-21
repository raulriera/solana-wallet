/// A SLIP-0010 path containing only hardened child indices.
public struct DerivationPath: Sendable, Equatable, CustomStringConvertible {
    /// The first account at `m/44'/501'/0'/0'`.
    public static let solana = DerivationPath(indices: [44, 501, 0, 0])

    /// A malformed path or an index outside the hardened derivation range.
    public enum ValidationError: Error, Equatable {
        /// The path isn't `m` followed by slash-separated hardened indices below 2³¹.
        case invalidPath
    }

    /// The bit that marks a child index as hardened; the indices a path names stay below it.
    static let hardenedBit: UInt32 = 0x8000_0000

    /// The child indices before adding the hardened bit.
    let indices: [UInt32]

    /// The child indices with the hardened bit set, as derivation uses them.
    var hardenedIndices: [UInt32] { indices.map { $0 | Self.hardenedBit } }

    /// The canonical path, with an apostrophe after each hardened child index.
    public var description: String { "m" + indices.map { "/\($0)'" }.joined() }

    /// Parses a hardened derivation path.
    ///
    /// For example, `m/44'/501'/1'/0'` selects the second account in the default
    /// Solana path family. The path `m` selects the master key.
    ///
    /// - Parameter path: A path beginning with `m`, followed by hardened child indices.
    /// - Throws: ``ValidationError/invalidPath`` for malformed or non-hardened paths.
    public init(_ path: String) throws {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard components.first == "m" else { throw ValidationError.invalidPath }
        indices = try components.dropFirst().map { component in
            let digits = component.dropLast()
            guard component.last == "'", !digits.isEmpty,
                  digits.utf8.allSatisfy({ (48...57).contains($0) }),
                  let index = UInt32(digits), index < Self.hardenedBit else {
                throw ValidationError.invalidPath
            }
            return index
        }
    }

    /// Creates a path from known, unhardened index values.
    ///
    /// - Parameter indices: Valid indices below 2³¹.
    init(indices: [UInt32]) {
        self.indices = indices
    }
}
