@testable import RPC

extension HTTPResponses {
    static func currency(error: RPCError? = nil, failingMethod: String? = nil) -> HTTPResponses {
        HTTPResponses([:], error: error, failingMethod: failingMethod, respond: CurrencyResponses.respond(to:))
    }
}
