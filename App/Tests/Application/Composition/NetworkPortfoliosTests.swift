import Foundation
import Observation
import Storage
import Testing
@testable import Portfolio
@testable import RPC
@testable import widgets

/// Checks that each network's portfolio service is created for the network's first window and then shared, that only
/// the network that the price provider quotes values holdings, that every service reads its prices again after each
/// currency change, and that every service ends the previous provider's work before windows observe a new connection.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct NetworkPortfoliosTests {
    /// Only mainnet's service exists until a window shows devnet; devnet's service is then created once.
    @Test
    func `Devnet's service is created for its first window and then reused`() {
        var made: [Network] = []
        let portfolios = NetworkPortfolios(prices: Jupiter(transport: HTTPResponses([:])),
                                           currency: .inMemory(), providers: .inMemory()) { network, _ in
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
                                           currency: .inMemory(), providers: .inMemory()) { network, prices in
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
        let portfolios = NetworkPortfolios(prices: prices, currency: currency, providers: .inMemory()) { network, _ in
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
        let portfolios = NetworkPortfolios(prices: Jupiter(transport: HTTPResponses([:])), currency: currency,
                                           providers: .inMemory()) { _, _ in
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
        let portfolios = NetworkPortfolios(prices: Jupiter(transport: HTTPResponses([:])), currency: currency,
                                           providers: .inMemory()) { _, _ in
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
        let providers = ProviderStore.inMemory()
        let portfolios = NetworkPortfolios(prices: Jupiter(transport: responses), currency: .inMemory(),
                                           providers: providers) { network, prices in
            Portfolio(rpc: responses.providerClient(network: network, providers: providers),
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

    /// A new provider ends every created service's work once, and the connection that windows observe follows only
    /// after; reading the settings ends no work.
    @Test
    func `A new provider ends every service's work before windows observe again`() async throws {
        let providers = ProviderStore.inMemory(key: StoredValue("fixture-key"))
        let gate = Suspension()
        let mainnet = PortfolioChanges(gate: gate)
        let devnet = PortfolioChanges()
        let portfolios = NetworkPortfolios(prices: Jupiter(transport: HTTPResponses([:])), currency: .inMemory(),
                                           providers: providers) { network, _ in
            network == .mainnet ? mainnet : devnet
        }
        _ = portfolios.makeCoordinator(for: .devnet)
        await providers.load()
        try await Self.connection(of: portfolios, becomes: .solana)

        try await providers.select(.helius)
        await gate.waitUntilStarted()
        #expect(portfolios.connection == .solana)
        gate.resume()
        try await Self.connection(of: portfolios, becomes: .helius(key: "fixture-key"))

        #expect(await mainnet.providerChanges == 1)
        #expect(await devnet.providerChanges == 1)
    }

    /// A new provider ends mainnet's work and creates no devnet service while no window has shown devnet.
    @Test
    func `A new provider creates no devnet service`() async throws {
        let providers = ProviderStore.inMemory(selection: .helius, key: "fixture-key")
        var made: [Network: PortfolioChanges] = [:]
        let portfolios = NetworkPortfolios(prices: Jupiter(transport: HTTPResponses([:])), currency: .inMemory(),
                                           providers: providers) { network, _ in
            let portfolio = PortfolioChanges()
            made[network] = portfolio
            return portfolio
        }
        await providers.load()
        try await Self.connection(of: portfolios, becomes: .helius(key: "fixture-key"))

        try await providers.select(.solana)
        try await Self.connection(of: portfolios, becomes: .solana)

        #expect(Set(made.keys) == [.mainnet])
        #expect(await made[.mainnet]?.providerChanges == 1)
    }

    /// Logos that one service can't remove don't keep another from ending its work, and windows still observe again.
    @Test
    func `A service that can't remove logos keeps no other from ending its work`() async throws {
        let providers = ProviderStore.inMemory(selection: .helius, key: "fixture-key")
        let failing = PortfolioChanges(error: CocoaError(.fileWriteOutOfSpace))
        let other = PortfolioChanges()
        let portfolios = NetworkPortfolios(prices: Jupiter(transport: HTTPResponses([:])), currency: .inMemory(),
                                           providers: providers) { network, _ in
            network == .mainnet ? failing : other
        }
        _ = portfolios.makeCoordinator(for: .devnet)
        await providers.load()
        try await Self.connection(of: portfolios, becomes: .helius(key: "fixture-key"))

        try await providers.select(.solana)
        try await Self.connection(of: portfolios, becomes: .solana)

        #expect(await other.providerChanges == 1)
    }

    /// A new key while Helius is in use is a new connection, which ends the work that read with the previous key.
    @Test
    func `A new Helius key ends the previous key's work`() async throws {
        let providers = ProviderStore.inMemory(selection: .helius, key: "fixture-key")
        let portfolio = PortfolioChanges()
        let portfolios = NetworkPortfolios(prices: Jupiter(transport: HTTPResponses([:])), currency: .inMemory(),
                                           providers: providers) { _, _ in portfolio }
        await providers.load()
        try await Self.connection(of: portfolios, becomes: .helius(key: "fixture-key"))

        try await providers.save(key: "fixture-key-2")
        try await Self.connection(of: portfolios, becomes: .helius(key: "fixture-key-2"))

        #expect(await portfolio.providerChanges == 1)
    }

    /// Edits that keep the connection end no work: a new key while another provider is in use, and deleting a custom
    /// RPC that isn't in use. The next provider then ends the work once, so it's the first change.
    @Test
    func `Edits that keep the connection end no work`() async throws {
        let unused = try #require(URL(string: "https://rpc.example.com"))
        let providers = ProviderStore.inMemory(StoredValue(ProviderSettings(customRPCs: [unused])),
                                               key: StoredValue("fixture-key"))
        let portfolio = PortfolioChanges()
        let portfolios = NetworkPortfolios(prices: Jupiter(transport: HTTPResponses([:])), currency: .inMemory(),
                                           providers: providers) { _, _ in portfolio }
        await providers.load()
        try await Self.connection(of: portfolios, becomes: .solana)

        try await providers.save(key: "fixture-key-2")
        try await providers.remove(unused)
        try await providers.select(.helius)
        try await Self.connection(of: portfolios, becomes: .helius(key: "fixture-key-2"))

        #expect(await portfolio.providerChanges == 1)
    }

    /// Erasing the settings, as a reset does, and the next read end no work, and windows see each at once.
    @Test
    func `Erasing the provider settings ends no work`() async throws {
        let providers = ProviderStore.inMemory(selection: .helius, key: "fixture-key")
        let portfolio = PortfolioChanges()
        let portfolios = NetworkPortfolios(prices: Jupiter(transport: HTTPResponses([:])), currency: .inMemory(),
                                           providers: providers) { _, _ in portfolio }
        await providers.load()
        try await Self.connection(of: portfolios, becomes: .helius(key: "fixture-key"))

        try await providers.erase()
        try await Self.connection(of: portfolios, becomes: nil)
        await providers.load()
        try await Self.connection(of: portfolios, becomes: .solana)

        #expect(await portfolio.providerChanges == 0)
    }

    /// Waits until the portfolios serve a connection.
    /// - Parameters:
    ///   - portfolios: The portfolios under test.
    ///   - connection: The connection to wait for.
    /// - Throws: `CancellationError` when the suite's time limit ends the wait.
    private static func connection(of portfolios: NetworkPortfolios,
                                   becomes connection: ProviderClient.Endpoint?) async throws {
        for await served in Observations({ portfolios.connection }) where served == connection { return }
        try Task.checkCancellation()
    }
}
