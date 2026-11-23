/// The optional features that a provider's server serves.
public struct Capabilities: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: Int

    /// Creates a set of capabilities from its raw bits.
    ///
    /// - Parameter rawValue: The bits of the capabilities in the set.
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// Creates a set that holds a capability when a check finds that the server serves it, or an empty set when the
    /// check fails for any reason but a rate limit or a cancellation.
    ///
    /// - Parameters:
    ///   - capability: The capability that the check looks for.
    ///   - check: The check, which returns whether the server serves the capability.
    /// - Throws: A rate-limit ``RPCError``, or `CancellationError`.
    init(_ capability: Capabilities, checking check: () async throws -> Bool) async throws {
        do {
            self = try await check() ? capability : []
        } catch let error as RPCError where error.isRateLimited {
            throw error
        } catch {
            try Task.checkCancellation()
            self = []
        }
    }

    /// Copies of token logos on the provider's own HTTPS image server.
    public static let logos = Capabilities(rawValue: 1 << 0)

    /// Private balances through a Solana Rings indexer and prover.
    public static let privateBalances = Capabilities(rawValue: 1 << 1)
}
