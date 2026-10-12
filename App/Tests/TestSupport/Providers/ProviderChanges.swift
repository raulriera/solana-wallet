import Foundation
import Portfolio
import Testing

/// Records provider changes on a portfolio, optionally suspending or failing each one, and reports any other use.
actor ProviderChanges: PortfolioProviding {
    private(set) var count = 0
    private let gate: Suspension?
    private let error: (any Error)?

    /// Creates a portfolio for one test.
    /// - Parameters:
    ///   - gate: An optional suspension inside each provider change.
    ///   - error: An optional error that each provider change throws after it runs.
    init(gate: Suspension? = nil, error: (any Error)? = nil) {
        self.gate = gate
        self.error = error
    }

    /// Records a provider change, then waits for the gate and throws the configured error.
    /// - Throws: The configured error, if any.
    func providerDidChange() async throws {
        count += 1
        await gate?.suspend()
        if let error { throw error }
    }

    /// Reports observation, because selecting a provider never observes a wallet.
    /// - Parameter owner: The requested wallet.
    /// - Returns: A finished stream.
    func observations(for owner: String) async -> AsyncStream<Update> {
        Issue.record("Selecting a provider must not observe a wallet.")
        return AsyncStream { $0.finish() }
    }

    /// Reports a refresh, because selecting a provider never reads balances.
    /// - Parameters:
    ///   - owner: The requested wallet.
    ///   - policy: The requested freshness policy.
    /// - Returns: A finished stream.
    func updates(for owner: String, policy: RefreshPolicy) async -> AsyncStream<Update> {
        Issue.record("Selecting a provider must not read balances.")
        return AsyncStream { $0.finish() }
    }

    /// Reports price work, because selecting a provider never reads prices.
    /// - Parameters:
    ///   - owner: The requested wallet.
    ///   - policy: The requested freshness policy.
    /// - Returns: A finished stream.
    func priceUpdates(for owner: String, policy: RefreshPolicy) async -> AsyncStream<Update> {
        Issue.record("Selecting a provider must not read prices.")
        return AsyncStream { $0.finish() }
    }

    /// Reports data removal, because selecting a provider keeps every wallet's data.
    /// - Parameter owner: The requested wallet.
    func removeData(for owner: String) async throws {
        Issue.record("Selecting a provider must not remove wallet data.")
    }
}
