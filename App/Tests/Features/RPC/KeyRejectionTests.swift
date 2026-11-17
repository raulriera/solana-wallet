import Foundation
import RPC
import Testing
@testable import widgets

struct KeyRejectionTests {
    @Test(arguments: [
        (RPCError.http(statusCode: 401, retryAfter: nil), true), (.http(statusCode: 403, retryAfter: nil), true),
        (.http(statusCode: 400, retryAfter: nil), false), (.http(statusCode: 404, retryAfter: nil), false),
        (.http(statusCode: 429, retryAfter: "5"), false), (.http(statusCode: 500, retryAfter: nil), false),
        (.server(code: 401, message: "Unauthorized"), false), (.transport(.userAuthenticationRequired), false),
    ])
    func `Only unauthorized and forbidden statuses reject the key`(_ error: RPCError, rejectsKey: Bool) {
        #expect(error.rejectsKey == rejectsKey)
    }
}
