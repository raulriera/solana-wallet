import Foundation
import Testing
@testable import RPC

/// Exercises the real European Central Bank adapter with recorded HTTP inputs and controlled response bodies.
struct EuropeanCentralBankTests {
    /// Reference rates in the bank's format: one euro buys 1.25 US dollars and 150 yen.
    private static let referenceRates = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gesmes:Envelope xmlns:gesmes="http://www.gesmes.org/xml/2002-08-01" \
        xmlns="http://www.ecb.int/vocabulary/2002-08-01/eurofxref">
            <gesmes:subject>Reference rates</gesmes:subject>
            <Cube>
                <Cube time='2026-10-23'>
                    <Cube currency='USD' rate='1.25'/>
                    <Cube currency='JPY' rate='150'/>
                </Cube>
            </Cube>
        </gesmes:Envelope>
        """

    /// Rates from the euro come as published, and rates from another currency go through the euro:
    /// one dollar buys 0.8 euros and 120 yen.
    /// - Parameters:
    ///   - currency: The currency to convert from.
    ///   - expected: The rates by hand: for the dollar, 1 / 1.25 euros and 150 / 1.25 yen.
    @Test(arguments: [
        ("EUR", ["EUR": Decimal(1), "USD": Decimal(string: "1.25")!, "JPY": 150]),
        ("USD", ["USD": Decimal(1), "EUR": Decimal(string: "0.8")!, "JPY": 120]),
    ])
    func `Rates convert through the euro`(currency: String, expected: [String: Decimal]) async throws {
        let transport = StubTransport { try httpReply(to: $0, body: Self.referenceRates) }
        let source: any ExchangeRateProviding = EuropeanCentralBank(transport: transport)

        #expect(try await source.rates(from: currency) == expected)
    }

    /// Rates come from one GET of the bank's daily reference file.
    @Test func `Rates come from the daily reference file`() async throws {
        let transport = StubTransport { try httpReply(to: $0, body: Self.referenceRates) }
        _ = try await EuropeanCentralBank(transport: transport).rates(from: "USD")

        let request = try #require(await transport.requests.first)
        #expect(await transport.requests.count == 1)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.absoluteString == "https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml")
    }

    /// A currency the bank doesn't publish has no rates, not zero rates.
    @Test func `An unpublished currency has no rates`() async throws {
        let transport = StubTransport { try httpReply(to: $0, body: Self.referenceRates) }
        #expect(try await EuropeanCentralBank(transport: transport).rates(from: "ARS").isEmpty)
    }

    /// Malformed or missing rates fail instead of inventing a rate.
    /// - Parameter body: An invalid response.
    @Test(arguments: [
        "<Cube><Cube currency='USD' rate='-1.25'/></Cube>",
        "<Cube><Cube currency='USD' rate='0'/></Cube>",
        "<Cube><Cube currency='USD' rate='soon'/></Cube>",
        "<Cube><Cube currency='USD'/></Cube>",
        "<Cube><Cube time='2026-10-23'/></Cube>",
        "<Cube><Cube currency='USD' rate='1.25'>",
        "{}",
    ])
    func `Invalid responses fail without inventing a rate`(_ body: String) async {
        let transport = StubTransport { try httpReply(to: $0, body: body) }
        await #expect(throws: RPCError.decoding) {
            try await EuropeanCentralBank(transport: transport).rates(from: "USD")
        }
    }
}
