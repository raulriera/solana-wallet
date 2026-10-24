public import Foundation

/// The European Central Bank's daily euro reference rates, through the shared exchange-rate contract.
///
/// The bank publishes about 30 currencies once each working day, without a key. Rates between two currencies other
/// than the euro go through the euro.
public struct EuropeanCentralBank: ExchangeRateProviding {
    private let transport: any HTTPTransport

    /// Creates a rate provider with an ephemeral URL session.
    public init() {
        self.init(transport: URLSessionTransport())
    }

    /// Creates a rate provider with an injected HTTP transport.
    /// - Parameter transport: The transport performing real requests or supplying HTTP test fixtures.
    init(transport: any HTTPTransport) {
        self.transport = transport
    }

    /// Reads the latest reference rates and converts them to rates from the requested currency.
    /// - Parameter currency: The ISO code of the currency to convert from.
    /// - Returns: Rates keyed by ISO currency code, or none when the bank doesn't publish the currency.
    /// - Throws: An HTTP, transport, decoding, or cancellation error.
    @concurrent
    public func rates(from currency: String) async throws -> [String: Decimal] {
        try Task.checkCancellation()
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

    /// Reads the euro reference rates from the bank's XML; the private parser keeps its format from consumers.
    private final class ReferenceRates: NSObject, XMLParserDelegate {
        /// One euro in each currency, including the euro itself.
        private var rates = ["EUR": Decimal(1)]
        private var isValid = true

        /// Decodes the reference rates.
        /// - Parameter data: The bank's XML response.
        /// - Returns: One euro in each published currency, including the euro at 1.
        /// - Throws: A decoding error for malformed XML, a rate that isn't a positive number, or no rates.
        static func decode(_ data: Data) throws -> [String: Decimal] {
            let reader = ReferenceRates()
            let parser = XMLParser(data: data)
            parser.delegate = reader
            guard parser.parse(), reader.isValid, reader.rates.count > 1 else { throw RPCError.decoding }
            return reader.rates
        }

        /// Reads a rate from each `Cube` element that names a currency.
        /// - Parameters:
        ///   - parser: The parser reading the response.
        ///   - elementName: The element's name.
        ///   - namespaceURI: The element's namespace, if any.
        ///   - qName: The element's qualified name, if any.
        ///   - attributeDict: The element's attributes.
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
