import Foundation

extension Data {
    private static let derivationPrefix = Data("TSPP/derive/".utf8)

    private static let offchainSigningDomain = Data([0xff] + Array("solana offchain".utf8))

    /// Whether the data is a Solana Rings key derivation input, bare or in an off-chain message.
    var isDerivationInput: Bool {
        starts(with: Self.derivationPrefix) || offchainPayload?.starts(with: Self.derivationPrefix) == true
    }

    /// The payload of a Solana off-chain message version 0, or `nil` if the data isn't one.
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
