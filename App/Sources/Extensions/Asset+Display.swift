import Transactions

extension Asset {
    /// The metadata's symbol, or a fallback from the asset's identity, such as a short mint address.
    nonisolated var displaySymbol: String {
        switch self {
        case .nativeSOL: return "SOL"
        case .token(let mint):
            if let symbol = mint.metadata?.symbol { return symbol }
            return mint.address.formatted(.shortAddress)
        }
    }

    /// The metadata's name, or a fallback from the asset's identity.
    nonisolated var displayName: String {
        switch self {
        case .nativeSOL: return "Solana"
        case .token(let mint):
            if let name = mint.metadata?.name { return name }
            return displaySymbol
        }
    }
}
