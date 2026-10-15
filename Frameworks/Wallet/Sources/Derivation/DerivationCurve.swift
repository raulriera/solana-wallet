/// A curve's SLIP-0010 rules for hardened private key derivation.
protocol DerivationCurve: Sendable {
    /// The HMAC-SHA512 key that derives the master node from a seed, such as `ed25519 seed`.
    var label: String { get }

    /// Accepts or refuses a candidate key from one HMAC-SHA512 output.
    ///
    /// - Parameters:
    ///   - candidate: The left 32 bytes of the output, I_L.
    ///   - parent: The parent's 32-byte private key, or `nil` for the master key.
    /// - Returns: The 32-byte private key, or `nil` when SLIP-0010 requires another hash.
    func privateKey(candidate: [UInt8], parent: [UInt8]?) -> [UInt8]?
}
