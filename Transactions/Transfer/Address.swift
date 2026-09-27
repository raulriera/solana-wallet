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
}
