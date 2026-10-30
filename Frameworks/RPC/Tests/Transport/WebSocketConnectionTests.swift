import Foundation
import Testing
@testable import RPC

struct WebSocketConnectionTests {
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
        let bound = Task { try? await Task.sleep(for: .seconds(10)); outcome.finish() }
        defer { bound.cancel() }

        var results = outcomes.makeAsyncIterator()
        let result = try #require(await results.next())
        #expect(result is CancellationError)
    }
}
