import Foundation
import RPC
import Testing

struct PriceProvidingTests {
    @Test
    func `Prices look up unique mints in batches and merge their quotes`() async throws {
        let source = EchoPrices(batchSize: 2)

        let quotes = try await source.prices(for: ["a", "b", "a", "c", "b", "d", "e"])

        #expect(await source.batches.value == [["a", "b"], ["c", "d"], ["e"]])
        #expect(Set(quotes.keys) == ["a", "b", "c", "d", "e"])
        #expect(quotes["c"] == Quote(pricePerUnit: 1, currency: "USD", dayChange: nil))
    }

    @Test
    func `Providers without a batch size answer every mint at once`() async throws {
        let source = EchoPrices()

        _ = try await source.prices(for: (0..<120).map { "mint-\($0)" })

        #expect(await source.batches.value.map(\.count) == [120])
    }

    @Test
    func `Empty lookups ask the provider for nothing`() async throws {
        let source = EchoPrices()

        #expect(try await source.prices(for: []).isEmpty)
        #expect(await source.batches.value.isEmpty)
    }

    @Test
    func `A quote for a mint that wasn't requested fails the lookup`() async {
        let source = EchoPrices(extra: "unrequested")

        await #expect(throws: RPCError.decoding) { try await source.prices(for: ["a"]) }
    }

    @Test(arguments: [
        Quote(pricePerUnit: -1, currency: "USD", dayChange: nil),
        Quote(pricePerUnit: .nan, currency: "USD", dayChange: nil),
        Quote(pricePerUnit: 1, currency: "DOLLARS", dayChange: nil),
        Quote(pricePerUnit: 1, currency: "", dayChange: nil),
    ])
    func `An invalid quote fails the lookup`(quote: Quote) async {
        let source = EchoPrices(quote: quote)

        await #expect(throws: RPCError.decoding) { try await source.prices(for: ["a"]) }
    }

    @Test
    func `A failed batch fails the whole lookup without partial quotes`() async {
        let source = EchoPrices(batchSize: 1, failing: "b")

        await #expect(throws: RPCError.http(statusCode: 429, retryAfter: nil)) {
            try await source.prices(for: ["a", "b", "c"])
        }
        #expect(await source.batches.value == [["a"], ["b"]])
    }
}

private actor Batches {
    private(set) var value: [[String]] = []

    func append(_ batch: [String]) {
        value.append(batch)
    }
}

private struct EchoPrices: PriceProviding {
    let network: Network = .mainnet
    let batches = Batches()
    let batchSize: Int
    private let quote: Quote
    private let extra: String?
    private let failing: String?

    init(batchSize: Int = .max, quote: Quote = Quote(pricePerUnit: 1, currency: "USD", dayChange: nil),
         extra: String? = nil, failing: String? = nil) {
        self.batchSize = batchSize
        self.quote = quote
        self.extra = extra
        self.failing = failing
    }

    func response(for mints: [String]) async throws -> [String] {
        await batches.append(mints)
        if let failing, mints.contains(failing) { throw RPCError.http(statusCode: 429, retryAfter: nil) }
        return mints + (extra.map { [$0] } ?? [])
    }

    func quotes(from response: [String]) throws -> [String: Quote] {
        Dictionary(uniqueKeysWithValues: response.map { ($0, quote) })
    }
}
