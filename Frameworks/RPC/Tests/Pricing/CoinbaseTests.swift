import Foundation
import Testing
@testable import RPC

/// Exercises the real Coinbase adapter with recorded HTTP inputs and controlled response bodies.
struct CoinbaseTests {
    /// Rates keep their decimal digits, include the requested currency at 1, and leave out crypto assets.
    @Test func `Rates keep ISO currencies at their exact values`() async throws {
        let transport = StubTransport { request in
            try httpReply(to: request, body: #"""
                {"data":{"currency":"USD","rates":{"EUR":"0.8934200000000000000000000000001","JPY":"156.8",
                 "USD":"1.0","BTC":"0.0000091","SOL":"0.0052"}}}
                """#)
        }
        let source: any ExchangeRateProviding = Coinbase(transport: transport)

        let rates = try await source.rates(from: "USD")

        #expect(rates == ["USD": 1, "EUR": Decimal(string: "0.8934200000000000000000000000001")!,
                          "JPY": Decimal(string: "156.8")!])
    }

    /// Rates come from one GET that names the requested currency.
    @Test func `Rates come from one request for the currency`() async throws {
        let transport = StubTransport { try httpReply(to: $0, body: #"{"data":{"currency":"USD","rates":{}}}"#) }
        _ = try await Coinbase(transport: transport).rates(from: "USD")

        let request = try #require(await transport.requests.first)
        #expect(await transport.requests.count == 1)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.absoluteString == "https://api.coinbase.com/v2/exchange-rates?currency=USD")
    }

    /// A currency that isn't an ISO currency, such as a crypto asset, has no rates and sends no request.
    @Test func `A currency outside ISO codes has no rates`() async throws {
        let transport = StubTransport { try httpReply(to: $0, body: "{}") }
        #expect(try await Coinbase(transport: transport).rates(from: "SOL").isEmpty)
        #expect(await transport.requests.isEmpty)
    }

    /// Malformed rates, or rates from another currency than the one requested, fail instead of inventing a rate.
    /// - Parameter body: An invalid response.
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
            try await Coinbase(transport: transport).rates(from: "USD")
        }
    }
}
