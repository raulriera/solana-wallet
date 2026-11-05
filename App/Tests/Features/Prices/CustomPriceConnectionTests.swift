import Foundation
import Storage
import Testing
@testable import RPC
@testable import widgets

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct CustomPriceConnectionTests {
    nonisolated private static let price =
        #"{"So11111111111111111111111111111111111111112":{"pricePerUnit":150.5,"currency":"USD"}}"#

    @Test
    func `A server that prices SOL is saved and chosen`() async throws {
        let url = try #require(URL(string: "https://prices.example.com/v1?key=fixture-key"))
        let prices = StoredValue(PriceSettings(selection: .off))
        let transport = Self.pricedTransport()

        try await makeConnection(prices: prices, transport: transport)
            .connect("https://prices.example.com/v1?key=fixture-key")

        #expect(await prices.value == PriceSettings(selection: .custom(url), customServers: [url]))
        let request = try #require(await transport.requests.first)
        #expect(try requestedMints(request, query: "mints") == ["So11111111111111111111111111111111111111112"])
        #expect(await transport.requests.count == 1)
    }

    @Test(arguments: ["http://prices.example.com", "prices.example.com", ""])
    func `A URL that isn't HTTPS is rejected without a request`(entry: String) async {
        let prices = StoredValue<PriceSettings>()
        let transport = Self.pricedTransport()

        await #expect(throws: CustomPriceError.notHTTPS) {
            try await makeConnection(prices: prices, transport: transport).connect(entry)
        }

        #expect(await transport.requests.isEmpty)
        #expect(await prices.value == nil)
    }

    @Test
    func `A listed server is rejected without a request`() async throws {
        let url = try #require(URL(string: "https://prices.example.com"))
        let prices = StoredValue(PriceSettings(customServers: [url]))
        let transport = Self.pricedTransport()

        await #expect(throws: CustomPriceError.duplicate) {
            try await makeConnection(prices: prices, transport: transport)
                .connect(url.absoluteString)
        }

        #expect(await transport.requests.isEmpty)
        #expect(await prices.value == PriceSettings(customServers: [url]))
    }

    @Test(arguments: [
        ("{}", 200),
        (#"{"So11111111111111111111111111111111111111112":{"pricePerUnit":-1,"currency":"USD"}}"#, 200),
        (#"{"usdPrice":1}"#, 200),
        ("not json", 200),
        ("{}", 404),
        ("{}", 500),
    ])
    func `A server that doesn't price SOL is rejected`(body: String, status: Int) async {
        let prices = StoredValue<PriceSettings>()
        let transport = StubTransport { try httpReply(to: $0, body: body, status: status) }

        await #expect(throws: CustomPriceError.unreachable) {
            try await makeConnection(prices: prices, transport: transport)
                .connect("https://prices.example.com")
        }

        #expect(await prices.value == nil)
    }

    @Test
    func `A rate-limited check asks to try again`() async {
        let prices = StoredValue<PriceSettings>()
        let transport = StubTransport { try httpReply(to: $0, body: "{}", status: 429) }

        await #expect(throws: CustomPriceError.rateLimited) {
            try await makeConnection(prices: prices, transport: transport)
                .connect("https://prices.example.com")
        }

        #expect(await prices.value == nil)
    }

    @Test
    func `Unreadable price servers explain it without a request`() async {
        let transport = Self.pricedTransport()

        await #expect(throws: CustomPriceError.unavailable) {
            try await makeConnection(prices: StoredValue(failsLoading: true), transport: transport)
                .connect("https://prices.example.com")
        }

        #expect(await transport.requests.isEmpty)
    }

    @Test
    func `A checked server that can't be saved explains it`() async {
        let transport = Self.pricedTransport()

        await #expect(throws: CustomPriceError.storageFailed) {
            try await makeConnection(prices: StoredValue(failsSaving: true), transport: transport)
                .connect("https://prices.example.com")
        }
    }

    @Test
    func `A cancelled check saves nothing`() async {
        let gate = Suspension()
        let prices = StoredValue<PriceSettings>()
        let transport = StubTransport { request in
            await gate.suspend()
            try Task.checkCancellation()
            return try httpReply(to: request, body: Self.price)
        }
        let connection = makeConnection(prices: prices, transport: transport)
        let operation = Task { try await connection.connect("https://prices.example.com") }
        defer { operation.cancel() }
        await gate.waitUntilStarted()

        operation.cancel()
        gate.resume()

        await #expect(throws: CancellationError.self) { try await operation.value }
        #expect(await prices.value == nil)
    }

    @Test(arguments: [
        (CustomPriceError.notHTTPS, true), (.duplicate, true), (.unreachable, true),
        (.rateLimited, false), (.unavailable, false), (.storageFailed, false),
    ])
    func `Only rejected URLs show under the field`(error: CustomPriceError, rejectsEntry: Bool) {
        #expect(error.rejectsEntry == rejectsEntry)
    }

    private func makeConnection(prices: StoredValue<PriceSettings>, transport: StubTransport) -> CustomPriceConnection {
        CustomPriceConnection(prices: .inMemory(prices)) { CustomPrices(endpoint: $0, transport: transport) }
    }

    private static func pricedTransport() -> StubTransport {
        StubTransport { try httpReply(to: $0, body: price) }
    }
}
