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
    func `Devnet's service is created without prices for its first window and then reused`() async throws {
        var made: [Network] = []
        var priced: [Network] = []
        let devnet = PortfolioChanges()
        let portfolios = PortfolioStore(prices: JupiterPriceProvider(transport: HTTPResponses([:])),
                                        currency: .inMemory(), rpcStore: .inMemory(),
                                        priceStore: .inMemory()) { network, prices in
            made.append(network)
            if prices is JupiterPriceProvider { priced.append(network) }
            return network == .mainnet ? PortfolioChanges() : devnet
        }
        #expect(made == [.mainnet])

        let first = try await Self.observe(.fixture(index: 1), on: .devnet, of: portfolios, through: devnet)
        let second = try await Self.observe(.fixture(index: 2), on: .devnet, of: portfolios, through: devnet)

        #expect(made == [.mainnet, .devnet])
        #expect(priced == [.mainnet])
        first.cancel()
        second.cancel()
    }

    @Test(.timeLimit(.minutes(1)))
    func `Each new price provider has every service read its prices once`() async throws {
        let priceStore = PriceStore.inMemory()
        let currency = CurrencyStore.inMemory(StoredValue(CurrencySettings(rateSource: .coinbase)))
        let mainnet = PortfolioChanges(currency: currency)
        let devnet = PortfolioChanges(currency: currency)
        await priceStore.load()
        await currency.load()
        let portfolios = PortfolioStore(prices: JupiterPriceProvider(transport: HTTPResponses([:])), currency: currency,
                                        rpcStore: .inMemory(), priceStore: priceStore) { network, _ in
            network == .mainnet ? mainnet : devnet
        }
        let viewing = try await Self.observe(.fixture(index: 1), on: .devnet, of: portfolios, through: devnet)
        defer { viewing.cancel() }
        var mainnetReads = mainnet.priceReads.makeAsyncIterator()
        var devnetReads = devnet.priceReads.makeAsyncIterator()

        for provider in [PriceSettings.Provider.off, .jupiter] {
            try await priceStore.select(provider)
            _ = await mainnetReads.next()
            _ = await devnetReads.next()
        }
        try await currency.select(currencyCode: "JPY")

        let expected = CurrencySettings(rateSource: .coinbase, currencyCode: "JPY")
        let mainnetRead = await mainnetReads.next()
        let devnetRead = await devnetReads.next()
        #expect(mainnetRead == expected)
        #expect(devnetRead == expected)
        withExtendedLifetime(portfolios) {}
    }

    @Test
    func `A new provider ends every service's work before windows observe again`() async throws {
        let rpcStore = RPCStore.inMemory(key: StoredValue("fixture-key"))
        let gate = Suspension()
        let mainnet = PortfolioChanges(gate: gate)
        let devnet = PortfolioChanges()
        let portfolios = PortfolioStore(prices: JupiterPriceProvider(transport: HTTPResponses([:])), currency: .inMemory(),
                                        rpcStore: rpcStore, priceStore: .inMemory()) { network, _ in
            network == .mainnet ? mainnet : devnet
        }
        let account = try Account.fixture(index: 1)
        let viewing = await Self.observe(account, on: .devnet, of: portfolios, through: devnet)
        defer { viewing.cancel() }
        var observed = devnet.observedOwners.makeAsyncIterator()
        await rpcStore.load()

        try await rpcStore.select(.helius)
        await gate.waitUntilStarted()
        gate.resume()

        #expect(await observed.next() == account.address.value)
        #expect(await mainnet.providerChanges == 1)
        #expect(await devnet.providerChanges == 1)
    }

    @Test
    func `A new provider creates no devnet service`() async throws {
        let rpcStore = RPCStore.inMemory(selection: .helius, key: "fixture-key")
        var made: [Network: PortfolioChanges] = [:]
        let portfolios = PortfolioStore(prices: JupiterPriceProvider(transport: HTTPResponses([:])), currency: .inMemory(),
                                        rpcStore: rpcStore, priceStore: .inMemory()) { network, _ in
            let portfolio = PortfolioChanges(rpcStore: rpcStore)
            made[network] = portfolio
            return portfolio
        }
        await rpcStore.load()

        try await rpcStore.select(.solana)
        let mainnet = try #require(made[.mainnet])
        try await Self.change(of: mainnet, becomes: .solana)

        #expect(Set(made.keys) == [.mainnet])
        #expect(await mainnet.providerChanges == 1)
        withExtendedLifetime(portfolios) {}
    }

    @Test
    func `A service that can't remove logos keeps no other from ending its work`() async throws {
        let rpcStore = RPCStore.inMemory(selection: .helius, key: "fixture-key")
        let failing = PortfolioChanges(error: CocoaError(.fileWriteOutOfSpace))
        let other = PortfolioChanges(rpcStore: rpcStore)
        let portfolios = PortfolioStore(prices: JupiterPriceProvider(transport: HTTPResponses([:])), currency: .inMemory(),
                                        rpcStore: rpcStore, priceStore: .inMemory()) { network, _ in
            network == .mainnet ? failing : other
        }
        let viewing = try await Self.observe(.fixture(index: 1), on: .devnet, of: portfolios, through: other)
        defer { viewing.cancel() }
        await rpcStore.load()

        try await rpcStore.select(.solana)
        try await Self.change(of: other, becomes: .solana)

        #expect(await other.providerChanges == 1)
    }

    @Test
    func `A new Helius key ends the previous key's work`() async throws {
        let rpcStore = RPCStore.inMemory(selection: .helius, key: "fixture-key")
        let portfolio = PortfolioChanges(rpcStore: rpcStore)
        let portfolios = PortfolioStore(prices: JupiterPriceProvider(transport: HTTPResponses([:])), currency: .inMemory(),
                                        rpcStore: rpcStore, priceStore: .inMemory()) { _, _ in portfolio }
        await rpcStore.load()

        try await rpcStore.save(key: "fixture-key-2")
        try await Self.change(of: portfolio, becomes: .helius(key: "fixture-key-2"))

        #expect(await portfolio.providerChanges == 1)
        withExtendedLifetime(portfolios) {}
    }

    @Test
    func `Edits that keep the connection end no work`() async throws {
        let unused = try #require(URL(string: "https://rpc.example.com"))
        let rpcStore = RPCStore.inMemory(StoredValue(RPCSettings(customRPCs: [unused])),
                                         key: StoredValue("fixture-key"))
        let portfolio = PortfolioChanges(rpcStore: rpcStore)
        let portfolios = PortfolioStore(prices: JupiterPriceProvider(transport: HTTPResponses([:])), currency: .inMemory(),
                                        rpcStore: rpcStore, priceStore: .inMemory()) { _, _ in portfolio }
        await rpcStore.load()

        try await rpcStore.save(key: "fixture-key-2")
        try await rpcStore.remove(unused)
        try await rpcStore.select(.helius)
        try await Self.change(of: portfolio, becomes: .helius(key: "fixture-key-2"))

        #expect(await portfolio.providerChanges == 1)
        withExtendedLifetime(portfolios) {}
    }

    @Test
    func `Erasing the provider settings ends no work`() async throws {
        let rpcStore = RPCStore.inMemory(selection: .helius, key: "fixture-key")
        let portfolio = PortfolioChanges(rpcStore: rpcStore)
        let portfolios = PortfolioStore(prices: JupiterPriceProvider(transport: HTTPResponses([:])), currency: .inMemory(),
                                        rpcStore: rpcStore, priceStore: .inMemory()) { _, _ in portfolio }
        var reads = portfolio.connectionReads.makeAsyncIterator()
        await rpcStore.load()

        try await rpcStore.erase()
        await rpcStore.load()
        try await rpcStore.save(key: "fixture-key-2")
        try await rpcStore.select(.helius)

        #expect(await reads.next() == .helius(key: "fixture-key-2"))
        #expect(await portfolio.providerChanges == 1)
        withExtendedLifetime(portfolios) {}
    }

    @Test
    func `Erasing forgets every wallet's portfolio and its saved holdings`() async throws {
        let directory = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let responses = HTTPResponses(["getMultipleAccounts": [#"{"context":{"slot":1},"value":[null]}"#]])
        let snapshots = FileSnapshotStore(directory: directory)
        let portfolios = PortfolioStore.serving(Portfolio(
            rpc: responses.rpcProvider(network: .devnet, rpcStore: .inMemory()), store: snapshots,
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
                               becomes connection: SelectedRPCProvider.Endpoint) async throws {
        for await read in service.connectionReads where read == connection { return }
        try Task.checkCancellation()
    }
}
