import Foundation
import Testing
@testable import RPC

struct EuropeanCentralBankExchangeRateProviderTests {
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

    @Test(arguments: [
        ("EUR", ["EUR": Decimal(1), "USD": Decimal(string: "1.25")!, "JPY": 150]),
        ("USD", ["USD": Decimal(1), "EUR": Decimal(string: "0.8")!, "JPY": 120]),
    ])
    func `Rates convert through the euro`(currency: String, expected: [String: Decimal]) async throws {
        let transport = StubTransport { try httpReply(to: $0, body: Self.referenceRates) }
        let source: any ExchangeRateProviding = EuropeanCentralBankExchangeRateProvider(transport: transport)

        #expect(try await source.rates(from: currency) == expected)
    }

    @Test func `Rates come from the daily reference file`() async throws {
        let transport = StubTransport { try httpReply(to: $0, body: Self.referenceRates) }
        _ = try await EuropeanCentralBankExchangeRateProvider(transport: transport).rates(from: "USD")

        let request = try #require(await transport.requests.first)
        #expect(await transport.requests.count == 1)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.absoluteString == "https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml")
    }

    @Test func `Answers longer than one mebibyte fail`() async {
        let transport = StubTransport { try httpReply(to: $0, body: String(repeating: " ", count: 1_048_577)) }
        await #expect(throws: RPCError.invalidResponse(.oversized)) {
            try await EuropeanCentralBankExchangeRateProvider(transport: transport).rates(from: "USD")
        }
    }

    @Test func `An unpublished currency has no rates`() async throws {
        let transport = StubTransport { try httpReply(to: $0, body: Self.referenceRates) }
        #expect(try await EuropeanCentralBankExchangeRateProvider(transport: transport).rates(from: "ARS").isEmpty)
    }

    @Test(arguments: [
        "<Cube><Cube currency='USD' rate='soon'/></Cube>",
        "<Cube><Cube currency='USD'/></Cube>",
        "<Cube><Cube time='2026-10-23'/></Cube>",
        "<Cube><Cube currency='USD' rate='1.25'>",
        "{}",
    ])
    func `Invalid responses fail without inventing a rate`(_ body: String) async {
        let transport = StubTransport { try httpReply(to: $0, body: body) }
        await #expect(throws: RPCError.decoding) {
            try await EuropeanCentralBankExchangeRateProvider(transport: transport).rates(from: "USD")
        }
    }
}
