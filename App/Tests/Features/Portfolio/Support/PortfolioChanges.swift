import Foundation
import Portfolio
import Testing
import Transactions
@testable import widgets

actor PortfolioChanges: PortfolioProviding {
    private(set) var providerChanges = 0
    nonisolated let connectionReads: AsyncStream<SelectedRPCProvider.Endpoint?>
    private let connectionReadsContinuation: AsyncStream<SelectedRPCProvider.Endpoint?>.Continuation
    nonisolated let priceReads: AsyncStream<CurrencySettings?>
    private let priceReadsContinuation: AsyncStream<CurrencySettings?>.Continuation
    nonisolated let observedOwners: AsyncStream<String>
    private let observedOwnersContinuation: AsyncStream<String>.Continuation
    private let gate: Suspension?
    private let error: (any Error)?
    private let currency: CurrencyStore?
    private let rpcStore: RPCStore?

    init(gate: Suspension? = nil, error: (any Error)? = nil, currency: CurrencyStore? = nil,
         rpcStore: RPCStore? = nil) {
        self.gate = gate
        self.error = error
        self.currency = currency
        self.rpcStore = rpcStore
        (connectionReads, connectionReadsContinuation) = AsyncStream.makeStream()
        (priceReads, priceReadsContinuation) = AsyncStream.makeStream()
        (observedOwners, observedOwnersContinuation) = AsyncStream.makeStream()
    }

    func providerDidChange() async throws {
        providerChanges += 1
        if let rpcStore { connectionReadsContinuation.yield(await rpcStore.connection) }
        await gate?.suspend()
        if let error { throw error }
    }

    func pricesDidChange() async {
        if let currency { priceReadsContinuation.yield(await currency.settings) }
    }

    func observations(for owner: String) async -> AsyncStream<Update> {
        observedOwnersContinuation.yield(owner)
        return AsyncStream { _ in }
    }

    func updates(for owner: String) async -> AsyncStream<Update> {
        Issue.record("Changing settings must not read balances.")
        return AsyncStream { $0.finish() }
    }

    func reload(for owner: String) async {
        Issue.record("Changing settings must not read balances.")
    }

    func removeData(for owner: String) async throws {
        Issue.record("Changing settings must not remove wallet data.")
    }
}

extension PortfolioChanges: TokenListProviding {
    func addToken(_ token: ListedToken, for owner: String) async throws {
        Issue.record("Changing settings must not edit token lists.")
        throw TokenListError.unreadable
    }

    func removeToken(_ mint: Address, for owner: String) async throws {
        Issue.record("Changing settings must not edit token lists.")
        throw TokenListError.unreadable
    }

    func token(at mint: Address) async throws -> TokenPreview {
        Issue.record("Changing settings must not look up tokens.")
        throw TokenLookupError.notToken
    }
}
