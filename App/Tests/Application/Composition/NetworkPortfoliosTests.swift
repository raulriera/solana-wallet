import Foundation
import Observation
import Storage
import Testing
@testable import Portfolio
@testable import RPC
@testable import widgets

/// Checks that each network's portfolio service is created for the network's first window and then shared, that only
/// the network that the price provider quotes values holdings, and that every service reads its prices again after
/// each currency change.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct NetworkPortfoliosTests {
    /// Only mainnet's service exists until a window shows devnet; devnet's service is then created once.
    @Test
    func `Devnet's service is created for its first window and then reused`() {
        var made: [Network] = []
        let portfolios = NetworkPortfolios(prices: Jupiter(transport: HTTPResponses([:])),
                                           currency: .inMemory()) { network, _ in
            made.append(network)
            return PortfolioChanges()
        }
        #expect(made == [.mainnet])
        #expect(portfolios.created.count == 1)

        _ = portfolios.makeCoordinator(for: .devnet)
        _ = portfolios.makeCoordinator(for: .devnet)
        _ = portfolios.makeCoordinator(for: .mainnet)

        #expect(made == [.mainnet, .devnet])
        #expect(portfolios.created.count == 2)
    }

    /// Mainnet's service gets the price provider, which quotes mainnet; devnet's service gets none.
    @Test
    func `Only mainnet's service gets the price provider`() {
        var priced: [Network: Bool] = [:]
        let portfolios = NetworkPortfolios(prices: Jupiter(transport: HTTPResponses([:])),
                                           currency: .inMemory()) { network, prices in
            priced[network] = prices is Jupiter
            return PortfolioChanges()
        }

        _ = portfolios.makeCoordinator(for: .devnet)

        #expect(priced == [.mainnet: true, .devnet: false])
    }

    /// Each change to the currency choice has every created service read its prices once, with the new choice;
    /// reading the saved choice and choosing what's already chosen read nothing, or the first read would show them.
    @Test
    func `Each currency change has every service read its prices once`() async throws {
        let currency = CurrencyStore.inMemory(StoredValue(CurrencySettings(rateSource: .coinbase)))
        let mainnet = PortfolioChanges(currency: currency)
        let devnet = PortfolioChanges(currency: currency)
        let prices = Jupiter(transport: HTTPResponses([:]))
        let portfolios = NetworkPortfolios(prices: prices, currency: currency) { network, _ in
            network == .mainnet ? mainnet : devnet
        }
        _ = portfolios.makeCoordinator(for: .devnet)
        var mainnetReads = mainnet.priceReads.makeAsyncIterator()
        var devnetReads = devnet.priceReads.makeAsyncIterator()

        await currency.load()
        try await currency.select(.coinbase)
        for code in ["EUR", "JPY"] {
            try await currency.select(currencyCode: code)

            let expected = CurrencySettings(rateSource: .coinbase, currencyCode: code)
            let mainnetRead = await mainnetReads.next()
            let devnetRead = await devnetReads.next()
            #expect(mainnetRead == expected)
            #expect(devnetRead == expected)
        }
        withExtendedLifetime(portfolios) {}
    }

    /// A change that can't be saved is undone, and the services then read their prices with the saved choice.
    @Test
    func `An unsaved currency change ends with the saved choice`() async throws {
        let saved = CurrencySettings(rateSource: .coinbase)
        let currency = CurrencyStore.inMemory(StoredValue(saved, failsSaving: true))
        let portfolio = PortfolioChanges(currency: currency)
        let portfolios = NetworkPortfolios(prices: Jupiter(transport: HTTPResponses([:])), currency: currency) { _, _ in
            portfolio
        }
        var reads = portfolio.priceReads.makeAsyncIterator()
        await currency.load()

        await #expect(throws: CocoaError.self) { try await currency.select(currencyCode: "EUR") }

        // The change shows before its save fails, so a read may see it before the undo.
        var read = await reads.next()
        if read == CurrencySettings(rateSource: .coinbase, currencyCode: "EUR") { read = await reads.next() }
        #expect(read == saved)
        withExtendedLifetime(portfolios) {}
    }

    /// Erasing the choice, as a reset does, and the next read have no service read its prices; the next change does,
    /// so the first price read shows that change.
    @Test
    func `Erasing the currency choice reads no prices`() async throws {
        let currency = CurrencyStore.inMemory(StoredValue(CurrencySettings(rateSource: .coinbase, currencyCode: "EUR")))
        let portfolio = PortfolioChanges(currency: currency)
        let portfolios = NetworkPortfolios(prices: Jupiter(transport: HTTPResponses([:])), currency: currency) { _, _ in
            portfolio
        }
        var reads = portfolio.priceReads.makeAsyncIterator()
        await currency.load()

        try await currency.erase()
        await currency.load()
        // Lists a source's currencies, as the Currency screen does, so the read and the change arrive apart.
        _ = try await currency.currencies(for: .europeanCentralBank)
        try await currency.select(currencyCode: "JPY")

        let read = await reads.next()
        #expect(read == CurrencySettings(currencyCode: "JPY"))
        withExtendedLifetime(portfolios) {}
    }

    /// A devnet window reads balances at the selected provider's devnet host, starting with SOL alone, and shows
    /// amounts without value because the price provider quotes mainnet.
    /// - Throws: A portfolio failure or a test prerequisite error.
    @Test
    func `A devnet window reads devnet balances without value`() async throws {
        let directory = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let responses = HTTPResponses(["getMultipleAccounts": [#"{"context":{"slot":1},"value":[null]}"#]])
        let portfolios = NetworkPortfolios(prices: Jupiter(transport: responses),
                                           currency: .inMemory()) { network, prices in
            Portfolio(rpc: responses.providerClient(network: network, settings: StoredValue<ProviderSettings>(),
                                                    providerKey: StoredValue<String>()),
                      store: FileSnapshotStore(directory: directory),
                      tokenLists: FileTokenListStore(directory: directory.appendingPathComponent("TokenLists")),
                      prices: prices)
        }
        let coordinator = portfolios.makeCoordinator(for: .devnet)
        let viewing = Task { await coordinator.observe(for: PublicWallet.address, isActive: true) }
        defer { viewing.cancel() }

        for await update in Observations({ coordinator.update }) {
            if let error = update?.error { throw error }
            if update?.isRefreshing == false, update?.snapshot != nil { break }
        }

        #expect(coordinator.update?.snapshot?.network == .devnet)
        #expect(coordinator.holdings.map(\.symbol) == ["SOL"])
        #expect(coordinator.holdings.allSatisfy { $0.valuation == nil })
        #expect(await responses.requests.map { $0.url?.host() } == ["api.devnet.solana.com"])
        viewing.cancel()
        await viewing.value
    }
}
