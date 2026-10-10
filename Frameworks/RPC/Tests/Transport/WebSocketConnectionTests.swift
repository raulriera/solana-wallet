import Foundation
import Testing
@testable import RPC

/// Verifies the URLSession WebSocket transport against a local server.
struct WebSocketConnectionTests {
    /// Verifies a ping whose pong never arrives stops waiting when its task is cancelled.
    ///
    /// - Throws: A server setup error or failed prerequisite.
    @Test(.timeLimit(.minutes(1)))
    func `A ping without a pong ends when its task is cancelled`() async throws {
        let server = try await SilentWebSocketServer()
        defer { server.stop() }
        let socket = URLSessionSocket(endpoint: server.endpoint)
        defer { socket.cancel() }
        let (outcomes, outcome) = AsyncStream<(any Error)?>.makeStream()
        let ping = Task {
            do { try await socket.ping(); outcome.yield(nil) } catch { outcome.yield(error) }
        }
        var pings = server.pings.makeAsyncIterator()
        _ = try #require(await pings.next())

        ping.cancel()
        // A ping that ignores cancellation never ends, so a bound stops the wait before the time limit.
        let bound = Task { try? await Task.sleep(for: .seconds(10)); outcome.finish() }
        defer { bound.cancel() }

        var results = outcomes.makeAsyncIterator()
        let result = try #require(await results.next())
        #expect(result is CancellationError)
    }
}
