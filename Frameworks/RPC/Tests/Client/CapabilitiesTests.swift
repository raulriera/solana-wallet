import Foundation
import Testing
@testable import RPC

struct CapabilitiesTests {
    @Test(
        arguments: [
            (.success(true), Capabilities.logos),
            (.success(false), Capabilities()),
            (.failure(.server(code: -32601, message: "Method not found")), Capabilities()),
        ] as [(Result<Bool, RPCError>, Capabilities)]
    )
    func `A check gives its capability only when the server serves it`(
        answer: Result<Bool, RPCError>,
        capabilities: Capabilities
    ) async throws {
        #expect(try await Capabilities(.logos) { try answer.get() } == capabilities)
    }

    @Test
    func `A rate-limited check throws`() async {
        await #expect(throws: RPCError.http(statusCode: 429, retryAfter: nil)) {
            try await Capabilities(.logos) { throw RPCError.http(statusCode: 429, retryAfter: nil) }
        }
    }

    @Test
    func `A cancelled check throws a cancellation`() async {
        let gate = Suspension()
        let check = Task {
            try await Capabilities(.logos) {
                await gate.suspend()
                throw URLError(.cancelled)
            }
        }
        await gate.waitUntilStarted()

        check.cancel()

        await #expect(throws: CancellationError.self) { try await check.value }
    }
}
