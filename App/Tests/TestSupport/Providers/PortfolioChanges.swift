import Foundation
import Portfolio
import Testing
import Transactions
@testable import widgets

/// Records provider changes on a portfolio, optionally suspending or failing each one, and the currency choice that
/// each price change reads, and reports any other use.
actor PortfolioChanges: PortfolioProviding {
    private(set) var providerChanges = 0
    /// The currency choice that each price change read, in order, when the portfolio reads one.
    nonisolated let priceReads: AsyncStream<CurrencySettings?>
    private let priceReadsContinuation: AsyncStream<CurrencySettings?>.Continuation
    private let gate: Suspension?
    private let error: (any Error)?
    private let currency: CurrencyStore?

    /// Creates a portfolio for one test.
    /// - Parameters:
    ///   - gate: An optional suspension inside each provider change.
    ///   - error: An optional error that each provider change throws after it runs.
    ///   - currency: An optional currency choice that each price change reads, as a real portfolio's prices do.
    init(gate: Suspension? = nil, error: (any Error)? = nil, currency: CurrencyStore? = nil) {
        self.gate = gate
        self.error = error
        self.currency = currency
        (priceReads, priceReadsContinuation) = AsyncStream.makeStream()
    }

    /// Records a provider change, then waits for the gate and throws the configured error.
    /// - Throws: The configured error, if any.
    func providerDidChange() async throws {
        providerChanges += 1
        await gate?.suspend()
        if let error { throw error }
    }

    /// Records the currency choice that a price change reads.
    func pricesDidChange() async {
        if let currency { priceReadsContinuation.yield(await currency.settings) }
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
