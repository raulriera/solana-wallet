import Foundation
import RPC
import Testing
@testable import widgets

struct KeyRejectionTests {
    @Test(arguments: [401, 403])
    func `Unauthorized and forbidden statuses reject the key`(status: Int) {
        #expect(RPCError.http(statusCode: status, retryAfter: nil).rejectsKey)
    }

    @Test(arguments: [
        RPCError.http(statusCode: 400, retryAfter: nil), .http(statusCode: 404, retryAfter: nil),
        .http(statusCode: 429, retryAfter: "5"), .http(statusCode: 500, retryAfter: nil),
        .server(code: 401, message: "Unauthorized"), .transport(.userAuthenticationRequired),
    ])
    func `Other failures don't reject the key`(_ error: RPCError) {
        #expect(!error.rejectsKey)
    }
}
