@testable import RPC

extension HTTPResponses {
    /// Answers price and exchange-rate lookups through the real adapters with ``CurrencyResponses``' fixtures.
    /// - Parameters:
    ///   - error: An optional HTTP or transport failure.
    ///   - failingMethod: The path whose requests fail with `error`, or `nil` for every request.
    /// - Returns: A request-recording transport for the price and rate adapters.
    static func currency(error: RPCError? = nil, failingMethod: String? = nil) -> HTTPResponses {
        HTTPResponses([:], error: error, failingMethod: failingMethod, respond: CurrencyResponses.respond(to:))
    }
}
