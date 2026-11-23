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
    func `A cancelled check throws a cancellation`() async throws {
        let (started, startedContinuation) = AsyncStream<Void>.makeStream()
        let (pending, release) = AsyncStream<Void>.makeStream()
        defer {
            startedContinuation.finish()
            release.finish()
        }
        let check = Task {
            try await Capabilities(.logos) {
                startedContinuation.yield(())
                for await _ in pending {}
                throw URLError(.cancelled)
            }
        }
        defer { check.cancel() }
        var iterator = started.makeAsyncIterator()
        _ = try #require(await iterator.next())

        check.cancel()

        await #expect(throws: CancellationError.self) { try await check.value }
    }
}
