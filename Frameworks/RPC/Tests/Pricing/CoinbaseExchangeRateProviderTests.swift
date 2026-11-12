import Foundation
import Testing
@testable import RPC

struct CoinbaseExchangeRateProviderTests {
    @Test func `Rates keep ISO currencies at their exact values`() async throws {
        let transport = StubTransport { request in
            try httpReply(to: request, body: #"""
                {"data":{"currency":"USD","rates":{"EUR":"0.8934200000000000000000000000001","JPY":"156.8",
                 "USD":"1.0","BTC":"0.0000091","SOL":"0.0052"}}}
                """#)
        }
        let source: any ExchangeRateProviding = CoinbaseExchangeRateProvider(transport: transport)

        let rates = try await source.rates(from: "USD")

        #expect(rates == ["USD": 1, "EUR": Decimal(string: "0.8934200000000000000000000000001")!,
                          "JPY": Decimal(string: "156.8")!])
    }

    @Test func `Rates come from one request for the currency`() async throws {
        let transport = StubTransport { try httpReply(to: $0, body: #"{"data":{"currency":"USD","rates":{}}}"#) }
        _ = try await CoinbaseExchangeRateProvider(transport: transport).rates(from: "USD")

        let request = try #require(await transport.requests.first)
        #expect(await transport.requests.count == 1)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.absoluteString == "https://api.coinbase.com/v2/exchange-rates?currency=USD")
    }

    @Test func `Answers longer than one mebibyte fail`() async {
        let padding = String(repeating: " ", count: 1_048_576)
        let body = #"{"data":{"currency":"USD","rates":{}}"# + padding + "}"
        let transport = StubTransport { try httpReply(to: $0, body: body) }
        await #expect(throws: RPCError.invalidResponse(.oversized)) {
            try await CoinbaseExchangeRateProvider(transport: transport).rates(from: "USD")
        }
    }

    @Test func `A currency outside ISO codes has no rates`() async throws {
        let transport = StubTransport { try httpReply(to: $0, body: "{}") }
        #expect(try await CoinbaseExchangeRateProvider(transport: transport).rates(from: "SOL").isEmpty)
        #expect(await transport.requests.isEmpty)
    }

    @Test(arguments: [
        #"{"data":{"currency":"EUR","rates":{"JPY":"175.5"}}}"#,
        #"{"data":{"currency":"USD","rates":{"EUR":"-0.89"}}}"#,
        #"{"data":{"currency":"USD","rates":{"EUR":"0"}}}"#,
        #"{"data":{"currency":"USD","rates":{"EUR":"soon"}}}"#,
        #"{"data":{"currency":"USD","rates":{"EUR":0.89}}}"#,
        #"{"data":{"currency":"USD"}}"#,
        #"[]"#,
    ])
    func `Invalid responses fail without inventing a rate`(_ body: String) async {
        let transport = StubTransport { try httpReply(to: $0, body: body) }
        await #expect(throws: RPCError.decoding) {
            try await CoinbaseExchangeRateProvider(transport: transport).rates(from: "USD")
        }
    }
}
