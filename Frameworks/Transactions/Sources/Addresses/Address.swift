import Encoding
/// A Solana account address validated as exactly 32 Base58-encoded bytes.
public struct Address: Sendable, Hashable {
    /// The original, case-sensitive ASCII Base58 representation.
    public let value: String
    let bytes: [UInt8]

    /// Creates an address without trimming, normalizing, or replacing characters.
    ///
    /// Validation checks encoding only; it doesn't prove ownership or account existence.
    /// Off-curve addresses, including program-derived addresses, are permitted.
    ///
    /// - Parameter value: The ASCII Base58 account address.
    /// - Throws: ``ValidationError/invalidAddress`` if the text doesn't encode 32 bytes.
    public init(_ value: String) throws {
        guard let bytes = Base58.decode(value, byteCount: 32) else { throw ValidationError.invalidAddress }
        self.value = value
        self.bytes = bytes
    }

    /// Creates an address from its bytes, such as a derived address or one read from account data.
    ///
    /// - Parameter bytes: The address's 32 bytes.
    /// - Throws: ``ValidationError/invalidAddress`` unless there are exactly 32 bytes.
    init(bytes: some Collection<UInt8>) throws {
        guard bytes.count == 32 else { throw ValidationError.invalidAddress }
        self.bytes = Array(bytes)
        value = Base58.encode(self.bytes)
    }

    /// Whether the address bytes decode to a point on the Ed25519 curve.
    ///
    /// `false` means no private key exists for the address, as with program-derived addresses.
    /// `true` means the bytes decode to an Ed25519 point, as every keypair address does; it doesn't
    /// prove a key exists, because small-order points decode but can't sign.
    ///
    /// The result never makes an address invalid; callers may warn, not reject.
    public var isOnCurve: Bool {
        EdwardsPoint.isOnCurve(bytes)
    }
}

extension Address: Codable {
    /// Decodes an address from its Base58 text, with the same validation as ``init(_:)``.
    ///
    /// - Parameter decoder: The decoder that supplies the address text.
    /// - Throws: A decoding error if the text doesn't encode 32 bytes.
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

    /// Encodes the address as its original Base58 text.
    ///
    /// - Parameter encoder: The encoder that receives the address text.
    /// - Throws: An encoding error if the text can't be written.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}
