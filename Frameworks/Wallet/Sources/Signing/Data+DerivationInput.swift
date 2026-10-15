import Foundation

extension Data {
    /// The payload prefix that Solana Rings reserves for key derivation messages.
    private static let derivationPrefix = Data("TSPP/derive/".utf8)

    /// The signing domain that begins every Solana off-chain message.
    private static let offchainSigningDomain = Data([0xff] + Array("solana offchain".utf8))

    /// Whether the message is a Solana Rings key derivation input, which signing must refuse.
    ///
    /// A derivation input starts with `TSPP/derive/`, bare or as the payload of a well-formed
    /// Solana off-chain message version 0, as zolana's `is_derivation_input` defines.
    var isDerivationInput: Bool {
        starts(with: Self.derivationPrefix) || offchainPayload?.starts(with: Self.derivationPrefix) == true
    }

    /// The payload of a well-formed Solana off-chain message version 0.
    ///
    /// The message is the signing domain, version 0, a 32-byte application domain, a format byte,
    /// a signer count, 32 bytes for each signer, a little-endian 16-bit length, and exactly that
    /// many payload bytes.
    private var offchainPayload: Data? {
        guard starts(with: Self.offchainSigningDomain) else { return nil }
        var rest = dropFirst(Self.offchainSigningDomain.count)
        guard rest.popFirst() == 0, rest.count >= 32 else { return nil }
        rest = rest.dropFirst(32)
        guard rest.popFirst() != nil, let signerCount = rest.popFirst(),
              rest.count >= 32 * Int(signerCount) else { return nil }
        rest = rest.dropFirst(32 * Int(signerCount))
        guard let low = rest.popFirst(), let high = rest.popFirst(),
              rest.count == Int(low) | Int(high) << 8 else { return nil }
        return rest
    }
}
