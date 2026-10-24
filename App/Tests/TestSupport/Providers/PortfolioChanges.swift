import Foundation
import Portfolio
import Testing
import Transactions

/// Records provider and price changes on a portfolio, optionally suspending or failing each provider change, and
/// reports any other use.
actor PortfolioChanges: PortfolioProviding {
    private(set) var providerChanges = 0
    private(set) var priceChanges = 0
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
        providerChanges += 1
        await gate?.suspend()
        if let error { throw error }
    }

    /// Records a price change.
    func pricesDidChange() async {
        priceChanges += 1
    }

    /// Reports observation, because changing settings never observes a wallet.
    /// - Parameter owner: The requested wallet.
    /// - Returns: A finished stream.
    func observations(for owner: String) async -> AsyncStream<Update> {
        Issue.record("Changing settings must not observe a wallet.")
        return AsyncStream { $0.finish() }
    }

    /// Reports a refresh, because changing settings never reads balances or prices itself.
    /// - Parameter owner: The requested wallet.
    /// - Returns: A finished stream.
    func updates(for owner: String) async -> AsyncStream<Update> {
        Issue.record("Changing settings must not read balances.")
        return AsyncStream { $0.finish() }
    }

    /// Reports data removal, because changing settings keeps every wallet's data.
    /// - Parameter owner: The requested wallet.
    func removeData(for owner: String) async throws {
        Issue.record("Changing settings must not remove wallet data.")
    }
}

extension PortfolioChanges: TokenListProviding {
    /// Reports a token-list edit, because changing settings never edits token lists.
    /// - Parameters:
    ///   - token: The token to add.
    ///   - owner: The requested wallet.
    /// - Throws: An unreadable-list error.
    func addToken(_ token: ListedToken, for owner: String) async throws {
        Issue.record("Changing settings must not edit token lists.")
        throw TokenListError.unreadable
    }

    /// Reports a token-list edit, because changing settings never edits token lists.
    /// - Parameters:
    ///   - mint: The token to remove.
    ///   - owner: The requested wallet.
    /// - Throws: An unreadable-list error.
    func removeToken(_ mint: Address, for owner: String) async throws {
        Issue.record("Changing settings must not edit token lists.")
        throw TokenListError.unreadable
    }

    /// Reports a token lookup, because changing settings never looks up tokens.
    /// - Parameter mint: The requested mint address.
    /// - Returns: Nothing; the lookup always fails.
    /// - Throws: A not-a-token error.
    func token(at mint: Address) async throws -> TokenPreview {
        Issue.record("Changing settings must not look up tokens.")
        throw TokenLookupError.notToken
    }
}
