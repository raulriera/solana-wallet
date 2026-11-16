/// Native SOL or a token.
public enum Asset: Codable, Sendable, Hashable, Identifiable {
    case nativeSOL
    case token(Mint)

    /// The identity of an asset on a network.
    public enum ID: Codable, Sendable, Hashable {
        case nativeSOL
        /// A token, identified by its mint address.
        case token(mint: Address)
    }

    public var id: ID {
        switch self {
        case .nativeSOL: .nativeSOL
        case .token(let mint): .token(mint: mint.address)
        }
    }

    /// The number of decimal places in the asset's base-unit amounts: 9 for SOL, whose base unit is the lamport, or
    /// the mint's for a token.
    public var decimals: UInt8 {
        switch self {
        case .nativeSOL: 9
        case .token(let mint): mint.decimals
        }
    }
}
