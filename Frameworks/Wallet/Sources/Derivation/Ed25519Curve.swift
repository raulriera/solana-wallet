/// SLIP-0010's Ed25519 rules, under which every 32-byte candidate is a private key.
struct Ed25519Curve: DerivationCurve {
    /// The master HMAC key that SLIP-0010 assigns to Ed25519.
    var label: String { "ed25519 seed" }

    /// Accepts every candidate unchanged, so Ed25519 derivation never hashes again.
    ///
    /// - Parameters:
    ///   - candidate: The left 32 bytes of the output, I_L.
    ///   - parent: The parent's private key, which doesn't affect an Ed25519 child.
    /// - Returns: `candidate`.
    func privateKey(candidate: [UInt8], parent: [UInt8]?) -> [UInt8]? {
        candidate
    }
}

extension DerivationCurve where Self == Ed25519Curve {
    /// SLIP-0010's Ed25519 rules, which Solana accounts use.
    static var ed25519: Self { Ed25519Curve() }
}
