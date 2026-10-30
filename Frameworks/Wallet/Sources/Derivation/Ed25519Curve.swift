/// SLIP-0010's Ed25519 rules, which accept every candidate key.
struct Ed25519Curve: DerivationCurve {
    var label: String { "ed25519 seed" }

    func privateKey(candidate: [UInt8], parent: [UInt8]?) -> [UInt8]? {
        candidate
    }
}

extension DerivationCurve where Self == Ed25519Curve {
    static var ed25519: Self { Ed25519Curve() }
}
