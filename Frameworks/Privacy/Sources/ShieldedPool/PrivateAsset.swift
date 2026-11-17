import ModularArithmetic
public import Transactions

/// An asset that private balances hold.
public enum PrivateAsset: Hashable, Sendable, CaseIterable {
    case nativeSOL
    case token(PrivateToken)

    public static let allCases: [PrivateAsset] = [.nativeSOL] + PrivateToken.supported.map(PrivateAsset.token)

    /// The pool's ID of the asset.
    var poolID: UInt64 {
        switch self {
        case .nativeSOL: 1
        case .token(let token): token.poolID
        }
    }

    /// The mint's 32 bytes, which are all zero for SOL.
    var mintBytes: [UInt8] {
        switch self {
        case .nativeSOL: [UInt8](repeating: 0, count: 32)
        case .token(let token): token.mint.bytes
        }
    }

    /// The asset's commitment in a UTXO's hash and a proof's public inputs.
    var commitment: Poseidon.Element {
        PackedBytes.hash32(mintBytes)
    }

    /// Creates the asset of a pool ID, or `nil` for an ID that private balances don't hold.
    ///
    /// - Parameter poolID: The pool's ID of the asset.
    init?(poolID: UInt64) {
        guard let asset = Self.allCases.first(where: { $0.poolID == poolID }) else { return nil }
        self = asset
    }

    /// Creates the asset of a mint, or `nil` for a mint that private balances don't hold.
    ///
    /// - Parameter mintBytes: The mint's 32 bytes.
    init?(mintBytes: [UInt8]) {
        guard let asset = Self.allCases.first(where: { $0.mintBytes == mintBytes }) else { return nil }
        self = asset
    }
}

extension PrivateAsset {
    /// Creates the private asset of an asset, or `nil` for a token that private balances don't hold.
    ///
    /// - Parameter asset: The asset.
    public init?(_ asset: Asset.ID) {
        switch asset {
        case .nativeSOL: self = .nativeSOL
        case .token(let mint):
            guard let token = PrivateToken(mint: mint) else { return nil }
            self = .token(token)
        }
    }

    /// The asset that private balances hold.
    public var asset: Asset.ID {
        switch self {
        case .nativeSOL: .nativeSOL
        case .token(let token): .token(mint: token.mint)
        }
    }
}

extension PrivateAsset: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        guard let asset = Self(poolID: try container.decode(UInt64.self)) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Private balances don't hold the asset.")
        }
        self = asset
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(poolID)
    }
}
