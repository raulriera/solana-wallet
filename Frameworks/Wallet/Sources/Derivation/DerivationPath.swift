/// A SLIP-0010 path containing only hardened child indices.
public struct DerivationPath: Sendable, Hashable, CustomStringConvertible {
    /// The path of the first Solana account, `m/44'/501'/0'/0'`.
    public static let solana = DerivationPath(indices: [44, 501, 0, 0])

    /// Returns the path of a Solana account.
    ///
    /// - Parameter account: The account index i, below 2³¹.
    /// - Returns: The path `m/44'/501'/i'/0'`.
    public static func solana(account: UInt32) -> Self {
        precondition(account < hardenedBit, "An account index must be below 2³¹.")
        return Self(indices: [44, 501, account, 0])
    }

    /// An error from parsing a derivation path.
    public enum ValidationError: Error, Equatable {
        /// The path isn't `m` followed by slash-separated hardened indices below 2³¹.
        case invalidPath
    }

    static let hardenedBit: UInt32 = 0x8000_0000

    /// The child indices without the hardened bit.
    let indices: [UInt32]

    var hardenedIndices: [UInt32] { indices.map { $0 | Self.hardenedBit } }

    /// The account index i of a path `m/44'/501'/i'/0'` or `m/44'/501'/i'`, or `nil` for any other path.
    public var accountIndex: UInt32? {
        guard indices.count == 3 || indices.count == 4 && indices[3] == 0, indices[0] == 44, indices[1] == 501 else {
            return nil
        }
        return indices[2]
    }

    public var description: String { "m" + indices.map { "/\($0)'" }.joined() }

    /// Creates a path by parsing its text, such as `m/44'/501'/1'/0'`.
    ///
    /// - Parameter path: A path beginning with `m`, followed by hardened child indices.
    /// - Throws: ``ValidationError/invalidPath`` for a malformed or non-hardened path.
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

    /// Creates a path from child indices without the hardened bit.
    ///
    /// - Parameter indices: Indices below 2³¹.
    init(indices: [UInt32]) {
        self.indices = indices
    }
}
