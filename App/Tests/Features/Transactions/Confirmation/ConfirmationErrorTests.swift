import RPC
import Testing
@testable import widgets

struct ConfirmationErrorTests {
    @Test(arguments: [
        (RPCError.http(statusCode: 429, retryAfter: "3") as any Error, ConfirmationError.rateLimited),
        (RPCError.server(code: 429, message: "Too many requests"), .rateLimited),
        (RPCProviderError.invalidKey, .invalidKey),
        (RPCError.http(statusCode: 401, retryAfter: nil), .unavailable),
        (RPCError.decoding, .unavailable),
    ])
    func `An error that stops a check maps to the reason it shows`(error: any Error, reason: ConfirmationError) {
        #expect(ConfirmationError(error) == reason)
    }
}
