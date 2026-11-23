/// The optional features that a provider's server serves.
public struct Capabilities: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: Int

    /// Creates a set of capabilities from its raw bits.
    ///
    /// - Parameter rawValue: The bits of the capabilities in the set.
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// Copies of token logos on the provider's own HTTPS image server.
    public static let logos = Capabilities(rawValue: 1 << 0)

    /// Private balances through a Solana Rings indexer and prover.
    public static let privateBalances = Capabilities(rawValue: 1 << 1)
}
