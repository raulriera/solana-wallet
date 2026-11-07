import Foundation
import Testing
@testable import RPC

struct ExchangeRateProvidingTests {
    enum Source: String, CaseIterable, CustomTestStringConvertible {
        case europeanCentralBank
        case coinbase

        var testDescription: String { rawValue }

        func provider(transport: StubTransport) -> any ExchangeRateProviding {
            switch self {
            case .europeanCentralBank: EuropeanCentralBankExchangeRateProvider(transport: transport)
            case .coinbase: CoinbaseExchangeRateProvider(transport: transport)
            }
        }
    }

    @Test(arguments: Source.allCases)
    func `Rate limits surface without retries`(source: Source) async throws {
        let transport = StubTransport { try httpReply(to: $0, body: "", status: 429, headers: ["Retry-After": "60"]) }
        await #expect(throws: RPCError.http(statusCode: 429, retryAfter: "60")) {
            try await source.provider(transport: transport).rates(from: "USD")
        }
        #expect(await transport.requests.count == 1)
    }

    @Test(.timeLimit(.minutes(1)), arguments: Source.allCases)
    func `Cancelling stops the request in flight`(source: Source) async throws {
        let (started, startedContinuation) = AsyncStream<Void>.makeStream()
        let (pending, release) = AsyncStream<Void>.makeStream()
        defer { startedContinuation.finish(); release.finish() }
        let transport = StubTransport { request in
            startedContinuation.yield(())
            for await _ in pending {}
            try Task.checkCancellation()
            return try httpReply(to: request, body: "")
        }
        let provider = source.provider(transport: transport)
        let operation = Task { try await provider.rates(from: "USD") }
        defer { operation.cancel() }
        var iterator = started.makeAsyncIterator()
        _ = try #require(await iterator.next())

        operation.cancel()

        await #expect(throws: CancellationError.self) { try await operation.value }
        #expect(await transport.observedCancellation)
    }
}
