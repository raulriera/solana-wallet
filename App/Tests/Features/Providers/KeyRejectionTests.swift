import Foundation
import RPC
import Testing
@testable import widgets

/// Verifies which provider failures mean that the API key was refused.
struct KeyRejectionTests {
    /// Verifies that unauthorized and forbidden statuses reject the key.
    /// - Parameter status: HTTP status 401 or 403.
    @Test(arguments: [401, 403])
    func `Unauthorized and forbidden statuses reject the key`(status: Int) {
        #expect(RPCError.http(statusCode: status, retryAfter: nil).rejectsKey)
    }

    /// Verifies that other failures, including other client errors and code 401 in a JSON-RPC reply, don't.
    /// - Parameter error: A failure that says nothing about the key.
    @Test(arguments: [
        RPCError.http(statusCode: 400, retryAfter: nil), .http(statusCode: 404, retryAfter: nil),
        .http(statusCode: 429, retryAfter: "5"), .http(statusCode: 500, retryAfter: nil),
        .server(code: 401, message: "Unauthorized"), .transport(.userAuthenticationRequired),
    ])
    func `Other failures don't reject the key`(_ error: RPCError) {
        #expect(!error.rejectsKey)
    }
}
