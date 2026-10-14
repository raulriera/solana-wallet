import Foundation
import Portfolio
import Testing
import Transactions

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

// The app's own TokenList view shares the framework type's name, so the module selector names the list.
extension ProviderChanges: TokenListProviding {
    /// Reports a token-list read, because selecting a provider never reads token lists.
    /// - Parameter owner: The requested wallet.
    /// - Returns: Nothing; the read always fails.
    /// - Throws: An unreadable-list error.
    func tokenList(for owner: String) async throws -> Portfolio::TokenList {
        Issue.record("Selecting a provider must not read token lists.")
        throw TokenListError.unreadable
    }

    /// Reports a token-list edit, because selecting a provider never edits token lists.
    /// - Parameters:
    ///   - token: The token to add.
    ///   - owner: The requested wallet.
    /// - Returns: Nothing; the edit always fails.
    /// - Throws: An unreadable-list error.
    func addToken(_ token: ListedToken, for owner: String) async throws -> Portfolio::TokenList {
        Issue.record("Selecting a provider must not edit token lists.")
        throw TokenListError.unreadable
    }

    /// Reports a token-list edit, because selecting a provider never edits token lists.
    /// - Parameters:
    ///   - mint: The token to remove.
    ///   - owner: The requested wallet.
    /// - Returns: Nothing; the edit always fails.
    /// - Throws: An unreadable-list error.
    func removeToken(_ mint: Address, for owner: String) async throws -> Portfolio::TokenList {
        Issue.record("Selecting a provider must not edit token lists.")
        throw TokenListError.unreadable
    }

    /// Reports a token lookup, because selecting a provider never looks up tokens.
    /// - Parameter mint: The requested mint address.
    /// - Returns: Nothing; the lookup always fails.
    /// - Throws: A not-a-token error.
    func token(at mint: Address) async throws -> TokenPreview {
        Issue.record("Selecting a provider must not look up tokens.")
        throw TokenLookupError.notToken
    }
}
