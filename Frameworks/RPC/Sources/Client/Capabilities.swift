/// The optional features that a provider's server serves.
public struct Capabilities: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// Creates a set with the capability when the check returns `true`, and an empty set when it returns `false` or
    /// fails.
    ///
    /// - Parameters:
    ///   - capability: The capability to check.
    ///   - check: The check that returns whether the server serves the capability.
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
