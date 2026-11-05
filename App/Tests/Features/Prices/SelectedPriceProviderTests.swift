import Foundation
import RPC
import Storage
import Synchronization
import Testing
@testable import widgets

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct SelectedPriceProviderTests {
    private static let server = URL(string: "https://prices.example.com/v1?key=fixture-key")!

    @Test
    func `Nothing saved looks up Jupiter's prices`() async throws {
        let jupiter = FixedPrices(currency: "USD")
        let custom = FixedPrices(currency: "EUR")
        let prices = SelectedPriceProvider(prices: .inMemory(), jupiter: jupiter) { _ in custom }

        let quotes = try await prices.prices(for: ["mint"])

        #expect(quotes == ["mint": Quote(pricePerUnit: 1, currency: "USD", dayChange: nil)])
        #expect(await jupiter.lookups.value == [["mint"]])
        #expect(await custom.lookups.value.isEmpty)
    }

    @Test
    func `A chosen server answers every lookup through one provider`() async throws {
        let custom = FixedPrices(currency: "EUR")
        let made = Mutex<[URL]>([])
        let store = PriceStore.inMemory(selection: .custom(Self.server))
        let prices = SelectedPriceProvider(prices: store, jupiter: FixedPrices(currency: "USD")) { url in
            made.withLock { $0.append(url) }
            return custom
        }

        _ = try await prices.prices(for: ["mint-a"])
        let quotes = try await prices.prices(for: ["mint-b"])

        #expect(quotes == ["mint-b": Quote(pricePerUnit: 1, currency: "EUR", dayChange: nil)])
        #expect(await custom.lookups.value == [["mint-a"], ["mint-b"]])
        #expect(made.withLock(\.self) == [Self.server])
    }

    @Test
    func `Prices that are off ask no provider`() async throws {
        let jupiter = FixedPrices(currency: "USD")
        let custom = FixedPrices(currency: "EUR")
        let prices = SelectedPriceProvider(prices: .inMemory(selection: .off), jupiter: jupiter) { _ in custom }

        #expect(try await prices.prices(for: ["mint"]).isEmpty)

        #expect(await jupiter.lookups.value.isEmpty)
        #expect(await custom.lookups.value.isEmpty)
    }

    @Test
    func `Each lookup reads the choice in use`() async throws {
        let jupiter = FixedPrices(currency: "USD")
        let store = PriceStore.inMemory()
        let prices = SelectedPriceProvider(prices: store, jupiter: jupiter) { _ in FixedPrices(currency: "EUR") }
        _ = try await prices.prices(for: ["mint"])

        try await store.select(.off)

        #expect(try await prices.prices(for: ["mint"]).isEmpty)
        #expect(await jupiter.lookups.value == [["mint"]])
    }

    @Test
    func `A saved server that can't be used fails the lookup`() async {
        let store = PriceStore.inMemory(selection: .custom(Self.server))
        let prices = SelectedPriceProvider(prices: store, jupiter: FixedPrices(currency: "USD")) { _ in nil }

        await #expect(throws: PricesError.unusableServer) { try await prices.prices(for: ["mint"]) }
    }

    @Test
    func `Unreadable settings fail the lookup without a request`() async {
        let jupiter = FixedPrices(currency: "USD")
        let store = PriceStore.inMemory(StoredValue(failsLoading: true))
        let prices = SelectedPriceProvider(prices: store, jupiter: jupiter) { _ in nil }

        await #expect(throws: PricesError.settingsUnreadable) { try await prices.prices(for: ["mint"]) }

        #expect(await jupiter.lookups.value.isEmpty)
    }
}

private actor Lookups {
    private(set) var value: [[String]] = []

    func append(_ mints: [String]) {
        value.append(mints)
    }
}

private struct FixedPrices: PriceProviding {
    let network: Network = .mainnet
    let currency: String
    let lookups = Lookups()

    func response(for mints: [String]) async throws -> [String: Quote] {
        await lookups.append(mints)
        let quote = Quote(pricePerUnit: 1, currency: currency, dayChange: nil)
        return Dictionary(uniqueKeysWithValues: mints.map { ($0, quote) })
    }

    func quotes(from response: [String: Quote]) -> [String: Quote] {
        response
    }
}
