import Encoding
/// A Solana account address validated as exactly 32 Base58-encoded bytes.
public struct Address: Sendable, Hashable {
    /// The address's Base58 text.
    public let value: String
    public let bytes: [UInt8]

    /// Creates an address from its Base58 text.
    ///
    /// - Parameter value: The Base58 account address.
    /// - Throws: ``ValidationError/invalidAddress`` if the text doesn't encode 32 bytes.
    public init(_ value: String) throws {
        guard let bytes = Base58.decode(value, byteCount: 32) else { throw ValidationError.invalidAddress }
        self.value = value
        self.bytes = bytes
    }

    /// Creates an address from its bytes.
    ///
    /// - Parameter bytes: The address's 32 bytes.
    /// - Throws: ``ValidationError/invalidAddress`` unless there are exactly 32 bytes.
    init(bytes: some Collection<UInt8>) throws {
        guard bytes.count == 32 else { throw ValidationError.invalidAddress }
        self.bytes = Array(bytes)
        value = Base58.encode(self.bytes)
    }

    /// A Boolean value that indicates whether the address bytes decode to a point on the Ed25519 curve.
    public var isOnCurve: Bool {
        EdwardsPoint.isOnCurve(bytes)
    }
}

extension Address: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        do {
            try self.init(value)
        } catch {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: container.codingPath, debugDescription: "Invalid Solana address.", underlyingError: error))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}
