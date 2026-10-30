public import Foundation

/// An exchange-rate provider backed by the European Central Bank's daily euro reference rates.
public struct EuropeanCentralBank: ExchangeRateProviding {
    private let transport: any HTTPTransport

    /// Creates a rate provider.
    public init() {
        self.init(transport: URLSessionTransport())
    }

    /// Creates a rate provider with an injected HTTP transport.
    ///
    /// - Parameter transport: The transport that performs HTTP requests.
    init(transport: any HTTPTransport) {
        self.transport = transport
    }

    @concurrent
    public func rates(from currency: String) async throws -> [String: Decimal] {
        try Task.checkCancellation()
        // swift-format-ignore: NeverForceUnwrap
        var request = URLRequest(url: URL(string: "https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml")!,
                                 timeoutInterval: 30)
        request.httpMethod = "GET"
        request.setValue("application/xml", forHTTPHeaderField: "Accept")
        let data = try await transport.responseData(for: request, redactor: SecretRedactor(secrets: []))
        let euroRates = try ReferenceRates.decode(data)
        try Task.checkCancellation()
        guard let base = euroRates[currency] else { return [:] }
        return euroRates.mapValues { $0 / base }
    }

    /// A parser for the bank's euro reference rates XML.
    private final class ReferenceRates: NSObject, XMLParserDelegate {
        /// One euro in each currency, including the euro itself.
        private var rates = ["EUR": Decimal(1)]
        private var isValid = true

        /// Decodes the reference rates.
        ///
        /// - Parameter data: The bank's XML response.
        /// - Returns: One euro in each published currency.
        /// - Throws: ``RPCError/decoding`` for invalid XML or rates.
        static func decode(_ data: Data) throws -> [String: Decimal] {
            let reader = ReferenceRates()
            let parser = XMLParser(data: data)
            parser.delegate = reader
            guard parser.parse(), reader.isValid, reader.rates.count > 1 else { throw RPCError.decoding }
            return reader.rates
        }

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
            guard elementName == "Cube", let code = attributeDict["currency"] else { return }
            guard let text = attributeDict["rate"],
                  let rate = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")),
                  !rate.isNaN, rate > 0 else {
                isValid = false
                parser.abortParsing()
                return
            }
            rates[code] = rate
        }
    }
}
