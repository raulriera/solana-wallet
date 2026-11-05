import Foundation
import Observation
import Storage
import Testing
import Transactions
@testable import Portfolio
@testable import RPC
@testable import widgets

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct PortfolioStoreTests {
    @Test
    func `Devnet's service is created for its first window and then reused`() async throws {
        var made: [Network] = []
        let devnet = PortfolioChanges()
        let portfolios = PortfolioStore(prices: Jupiter(transport: HTTPResponses([:])),
                                        currency: .inMemory(), providers: .inMemory(),
                                        priceChoice: .inMemory()) { network, _ in
            made.append(network)
            return network == .mainnet ? PortfolioChanges() : devnet
        }
        #expect(made == [.mainnet])

        let first = try await Self.observe(.fixture(index: 1), on: .devnet, of: portfolios, through: devnet)
        let second = try await Self.observe(.fixture(index: 2), on: .devnet, of: portfolios, through: devnet)

        #expect(made == [.mainnet, .devnet])
        first.cancel()
        second.cancel()
    }

    @Test
    func `Only mainnet's service gets the price provider`() async throws {
        var priced: [Network: Bool] = [:]
        let devnet = PortfolioChanges()
        let portfolios = PortfolioStore(prices: Jupiter(transport: HTTPResponses([:])),
                                        currency: .inMemory(), providers: .inMemory(),
                                        priceChoice: .inMemory()) { network, prices in
            priced[network] = prices is Jupiter
            return network == .mainnet ? PortfolioChanges() : devnet
        }

        let viewing = try await Self.observe(.fixture(index: 1), on: .devnet, of: portfolios, through: devnet)

        #expect(priced == [.mainnet: true, .devnet: false])
        viewing.cancel()
    }

    @Test
    func `Each currency change has every service read its prices once`() async throws {
        let currency = CurrencyStore.inMemory(StoredValue(CurrencySettings(rateSource: .coinbase)))
        let priceChoice = PriceStore.inMemory()
        let mainnet = PortfolioChanges(currency: currency)
        let devnet = PortfolioChanges(currency: currency)
        let prices = Jupiter(transport: HTTPResponses([:]))
        let portfolios = PortfolioStore(prices: prices, currency: currency, providers: .inMemory(),
                                        priceChoice: priceChoice) { network, _ in
            network == .mainnet ? mainnet : devnet
        }
        let viewing = try await Self.observe(.fixture(index: 1), on: .devnet, of: portfolios, through: devnet)
        defer { viewing.cancel() }
        var mainnetReads = mainnet.priceReads.makeAsyncIterator()
        var devnetReads = devnet.priceReads.makeAsyncIterator()

        await priceChoice.load()
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

    @Test
    func `An unsaved currency change ends with the saved choice`() async throws {
        let saved = CurrencySettings(rateSource: .coinbase)
        let currency = CurrencyStore.inMemory(StoredValue(saved, failsSaving: true))
        let priceChoice = PriceStore.inMemory()
        let portfolio = PortfolioChanges(currency: currency)
        let portfolios = PortfolioStore(prices: Jupiter(transport: HTTPResponses([:])), currency: currency,
                                        providers: .inMemory(), priceChoice: priceChoice) { _, _ in
            portfolio
        }
        var reads = portfolio.priceReads.makeAsyncIterator()
        await priceChoice.load()
        await currency.load()

        await #expect(throws: CocoaError.self) { try await currency.select(currencyCode: "EUR") }

        var read = await reads.next()
        if read == CurrencySettings(rateSource: .coinbase, currencyCode: "EUR") { read = await reads.next() }
        #expect(read == saved)
        withExtendedLifetime(portfolios) {}
    }

    @Test
    func `Erasing the currency choice reads no prices`() async throws {
        let currency = CurrencyStore.inMemory(StoredValue(CurrencySettings(rateSource: .coinbase, currencyCode: "EUR")))
        let priceChoice = PriceStore.inMemory()
        let portfolio = PortfolioChanges(currency: currency)
        let portfolios = PortfolioStore(prices: Jupiter(transport: HTTPResponses([:])), currency: currency,
                                        providers: .inMemory(), priceChoice: priceChoice) { _, _ in
            portfolio
        }
        var reads = portfolio.priceReads.makeAsyncIterator()
        await priceChoice.load()
        await currency.load()

        try await currency.erase()
        await currency.load()
        _ = try await currency.currencies(for: .europeanCentralBank)
        try await currency.select(currencyCode: "JPY")

        let read = await reads.next()
        #expect(read == CurrencySettings(currencyCode: "JPY"))
        withExtendedLifetime(portfolios) {}
    }

    @Test
    func `Each new price provider has every service read its prices once`() async throws {
        let priceChoice = PriceStore.inMemory()
        let currency = CurrencyStore.inMemory()
        let mainnet = PortfolioChanges(currency: currency)
        let devnet = PortfolioChanges(currency: currency)
        let portfolios = PortfolioStore(prices: Jupiter(transport: HTTPResponses([:])), currency: currency,
                                        providers: .inMemory(), priceChoice: priceChoice) { network, _ in
            network == .mainnet ? mainnet : devnet
        }
        let viewing = try await Self.observe(.fixture(index: 1), on: .devnet, of: portfolios, through: devnet)
        defer { viewing.cancel() }
        var mainnetReads = mainnet.priceReads.makeAsyncIterator()
        var devnetReads = devnet.priceReads.makeAsyncIterator()
        await priceChoice.load()
        await currency.load()

        for provider in [PriceSettings.Provider.off, .jupiter] {
            try await priceChoice.select(provider)
            _ = await mainnetReads.next()
            _ = await devnetReads.next()
        }

        withExtendedLifetime(portfolios) {}
    }

    @Test
    func `A devnet window reads devnet balances without value`() async throws {
        let directory = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let responses = HTTPResponses(["getMultipleAccounts": [#"{"context":{"slot":1},"value":[null]}"#]])
        let providers = ProviderStore.inMemory()
        let portfolios = PortfolioStore(prices: Jupiter(transport: responses), currency: .inMemory(),
                                        providers: providers, priceChoice: .inMemory()) { network, prices in
            Portfolio(rpc: responses.providerClient(network: network, providers: providers),
                      store: FileSnapshotStore(directory: directory),
                      tokenLists: tokenLists(in: directory), prices: prices)
        }
        let account = try Account.publicWallet()
        let viewing = Task { await portfolios.observe(account, on: .devnet) }
        defer { viewing.cancel() }

        for await update in Observations({ portfolios.portfolio(for: account, on: .devnet)?.update }) {
            if let error = update?.error { throw error }
            if update?.isRefreshing == false, update?.snapshot != nil { break }
        }

        let holdings = portfolios.portfolio(for: account, on: .devnet)?.holdings ?? []
        #expect(portfolios.portfolio(for: account, on: .devnet)?.update?.snapshot?.network == .devnet)
        #expect(holdings.map(\.symbol) == ["SOL"])
        #expect(holdings.allSatisfy { $0.valuation == nil })
        #expect(await responses.requests.map { $0.url?.host() } == ["api.devnet.solana.com"])
        viewing.cancel()
        await viewing.value
    }

    @Test
    func `A new provider ends every service's work before windows observe again`() async throws {
        let providers = ProviderStore.inMemory(key: StoredValue("fixture-key"))
        let gate = Suspension()
        let mainnet = PortfolioChanges(gate: gate)
        let devnet = PortfolioChanges()
        let portfolios = PortfolioStore(prices: Jupiter(transport: HTTPResponses([:])), currency: .inMemory(),
                                        providers: providers, priceChoice: .inMemory()) { network, _ in
            network == .mainnet ? mainnet : devnet
        }
        let account = try Account.fixture(index: 1)
        let viewing = await Self.observe(account, on: .devnet, of: portfolios, through: devnet)
        defer { viewing.cancel() }
        var observed = devnet.observedOwners.makeAsyncIterator()
        await providers.load()

        try await providers.select(.helius)
        await gate.waitUntilStarted()
        gate.resume()

        #expect(await observed.next() == account.address.value)
        #expect(await mainnet.providerChanges == 1)
        #expect(await devnet.providerChanges == 1)
    }

    @Test
    func `A new provider creates no devnet service`() async throws {
        let providers = ProviderStore.inMemory(selection: .helius, key: "fixture-key")
        var made: [Network: PortfolioChanges] = [:]
        let portfolios = PortfolioStore(prices: Jupiter(transport: HTTPResponses([:])), currency: .inMemory(),
                                        providers: providers, priceChoice: .inMemory()) { network, _ in
            let portfolio = PortfolioChanges(providers: providers)
            made[network] = portfolio
            return portfolio
        }
        await providers.load()

        try await providers.select(.solana)
        let mainnet = try #require(made[.mainnet])
        try await Self.change(of: mainnet, becomes: .solana)

        #expect(Set(made.keys) == [.mainnet])
        #expect(await mainnet.providerChanges == 1)
        withExtendedLifetime(portfolios) {}
    }

    @Test
    func `A service that can't remove logos keeps no other from ending its work`() async throws {
        let providers = ProviderStore.inMemory(selection: .helius, key: "fixture-key")
        let failing = PortfolioChanges(error: CocoaError(.fileWriteOutOfSpace))
        let other = PortfolioChanges(providers: providers)
        let portfolios = PortfolioStore(prices: Jupiter(transport: HTTPResponses([:])), currency: .inMemory(),
                                        providers: providers, priceChoice: .inMemory()) { network, _ in
            network == .mainnet ? failing : other
        }
        let viewing = try await Self.observe(.fixture(index: 1), on: .devnet, of: portfolios, through: other)
        defer { viewing.cancel() }
        await providers.load()

        try await providers.select(.solana)
        try await Self.change(of: other, becomes: .solana)

        #expect(await other.providerChanges == 1)
    }

    @Test
    func `A new Helius key ends the previous key's work`() async throws {
        let providers = ProviderStore.inMemory(selection: .helius, key: "fixture-key")
        let portfolio = PortfolioChanges(providers: providers)
        let portfolios = PortfolioStore(prices: Jupiter(transport: HTTPResponses([:])), currency: .inMemory(),
                                        providers: providers, priceChoice: .inMemory()) { _, _ in portfolio }
        await providers.load()

        try await providers.save(key: "fixture-key-2")
        try await Self.change(of: portfolio, becomes: .helius(key: "fixture-key-2"))

        #expect(await portfolio.providerChanges == 1)
        withExtendedLifetime(portfolios) {}
    }

    @Test
    func `Edits that keep the connection end no work`() async throws {
        let unused = try #require(URL(string: "https://rpc.example.com"))
        let providers = ProviderStore.inMemory(StoredValue(ProviderSettings(customRPCs: [unused])),
                                               key: StoredValue("fixture-key"))
        let portfolio = PortfolioChanges(providers: providers)
        let portfolios = PortfolioStore(prices: Jupiter(transport: HTTPResponses([:])), currency: .inMemory(),
                                        providers: providers, priceChoice: .inMemory()) { _, _ in portfolio }
        await providers.load()

        try await providers.save(key: "fixture-key-2")
        try await providers.remove(unused)
        try await providers.select(.helius)
        try await Self.change(of: portfolio, becomes: .helius(key: "fixture-key-2"))

        #expect(await portfolio.providerChanges == 1)
        withExtendedLifetime(portfolios) {}
    }

    @Test
    func `Erasing the provider settings ends no work`() async throws {
        let providers = ProviderStore.inMemory(selection: .helius, key: "fixture-key")
        let portfolio = PortfolioChanges(providers: providers)
        let portfolios = PortfolioStore(prices: Jupiter(transport: HTTPResponses([:])), currency: .inMemory(),
                                        providers: providers, priceChoice: .inMemory()) { _, _ in portfolio }
        var reads = portfolio.connectionReads.makeAsyncIterator()
        await providers.load()

        try await providers.erase()
        await providers.load()
        try await providers.save(key: "fixture-key-2")
        try await providers.select(.helius)

        #expect(await reads.next() == .helius(key: "fixture-key-2"))
        #expect(await portfolio.providerChanges == 1)
        withExtendedLifetime(portfolios) {}
    }

    @Test
    func `A new provider observes the observed wallets again`() async throws {
        let providers = ProviderStore.inMemory(selection: .helius, key: "fixture-key")
        let portfolio = PortfolioChanges()
        let portfolios = PortfolioStore(prices: Jupiter(transport: HTTPResponses([:])), currency: .inMemory(),
                                        providers: providers, priceChoice: .inMemory()) { _, _ in portfolio }
        var observed = portfolio.observedOwners.makeAsyncIterator()
        let account = try Account.fixture(index: 1)
        let first = Task { await portfolios.observe(account, on: .mainnet) }
        let second = Task { await portfolios.observe(account, on: .mainnet) }
        defer {
            first.cancel()
            second.cancel()
        }
        #expect(await observed.next() == account.address.value)
        await providers.load()

        try await providers.select(.solana)

        #expect(await observed.next() == account.address.value)
        #expect(await portfolio.providerChanges == 1)
    }

    @Test
    func `Windows on the same wallet share one observation`() async throws {
        let service = PortfolioResponses()
        let portfolios = PortfolioStore.serving(service)
        var requests = service.requests.makeAsyncIterator()
        let account = try Account.fixture(index: 1)
        let first = Task { await portfolios.observe(account, on: .devnet) }
        defer { first.cancel() }
        let observation = try #require(await requests.next())
        let second = Task { await portfolios.observe(account, on: .devnet) }
        defer { second.cancel() }
        let shared = Snapshot.fixture(owner: account.address.value, lamports: 1)
        observation.continuation.yield(Update(snapshot: shared, phase: .ready, revision: 1))
        for await snapshot in Observations({ portfolios.portfolio(for: account, on: .devnet)?.update?.snapshot })
        where snapshot == shared {
            break
        }

        first.cancel()
        await first.value
        let changed = Snapshot.fixture(owner: account.address.value, lamports: 2)
        observation.continuation.yield(Update(snapshot: changed, phase: .ready, revision: 2))
        for await snapshot in Observations({ portfolios.portfolio(for: account, on: .devnet)?.update?.snapshot })
        where snapshot == changed {
            break
        }
        second.cancel()
        await second.value
        for await _ in observation.termination {}

        #expect(await service.calls.count == 1)
        #expect(portfolios.portfolio(for: account, on: .mainnet) == nil)
        #expect(portfolios.portfolio(for: account, on: .devnet)?.update?.snapshot == changed)
    }

    @Test
    func `Erasing forgets every wallet's portfolio and its saved holdings`() async throws {
        let directory = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let responses = HTTPResponses(["getMultipleAccounts": [#"{"context":{"slot":1},"value":[null]}"#]])
        let snapshots = FileSnapshotStore(directory: directory)
        let portfolios = PortfolioStore.serving(Portfolio(
            rpc: responses.providerClient(network: .devnet, providers: .inMemory()), store: snapshots,
            tokenLists: tokenLists(in: directory)))
        let account = try Account.publicWallet()
        let viewing = Task { await portfolios.observe(account, on: .devnet) }
        defer { viewing.cancel() }
        for await update in Observations({ portfolios.portfolio(for: account, on: .devnet)?.update }) {
            if let error = update?.error { throw error }
            if update?.isRefreshing == false, update?.snapshot != nil { break }
        }

        try await portfolios.erase()

        #expect(portfolios.portfolio(for: account, on: .devnet) == nil)
        #expect(snapshots.snapshot(for: CacheKey(owner: account.address.value, network: .devnet)) == nil)
        viewing.cancel()
        await viewing.value
    }

    @Test
    func `Adding a token saves it to the wallet's list`() async throws {
        let directory = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let portfolios = PortfolioStore.serving(filePortfolio(in: directory))
        let bonk = ListedToken(mint: try Address("DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263"), program: .token,
                               decimals: 5, symbol: "Bonk", name: "Bonk")

        try await portfolios.add(bonk, for: Account.publicWallet(), on: .mainnet)

        #expect(try savedList(in: directory)?.tokens.last == bonk)
    }

    @Test
    func `Removing a token saves the wallet's list without it`() async throws {
        let directory = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let portfolios = PortfolioStore.serving(filePortfolio(in: directory))

        try await portfolios.remove(Address(DefaultToken.usdt.rawValue), for: Account.publicWallet(), on: .mainnet)

        #expect(try savedList(in: directory)?.tokens.map(\.mint.value) == [DefaultToken.usdc.rawValue])
    }

    private func filePortfolio(in directory: URL) -> Portfolio {
        Portfolio(rpc: Solana(network: .mainnet), store: FileSnapshotStore(directory: directory),
                  tokenLists: tokenLists(in: directory))
    }

    private func savedList(in directory: URL) throws -> Portfolio::TokenList? {
        try tokenLists(in: directory).tokenList(for: CacheKey(owner: PublicWallet.address, network: .mainnet))
    }

    private func tokenLists(in directory: URL) -> FileTokenListStore {
        FileTokenListStore(directory: directory.appendingPathComponent("TokenLists"))
    }

    private static func observe(_ account: widgets.Account, on network: Network, of portfolios: PortfolioStore,
                                through service: PortfolioChanges) async -> Task<Void, Never> {
        var observed = service.observedOwners.makeAsyncIterator()
        let viewing = Task { await portfolios.observe(account, on: network) }
        _ = await observed.next()
        return viewing
    }

    private static func change(of service: PortfolioChanges,
                               becomes connection: ProviderClient.Endpoint) async throws {
        for await read in service.connectionReads where read == connection { return }
        try Task.checkCancellation()
    }
}
