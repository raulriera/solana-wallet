import Foundation
import Network

/// A loopback WebSocket server that reads every frame but never answers a ping.
final class SilentWebSocketServer: Sendable {
    /// The server's loopback WebSocket address.
    let endpoint: URL
    /// Delivers one value each time a client's ping arrives.
    let pings: AsyncStream<Void>
    private let listening: Task<Void, any Error>

    /// Starts listening on a free port of the loopback interface only.
    /// - Throws: A Network framework error if the listener can't start.
    init() async throws {
        let loopback = NWParameters()
        loopback.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        let listener = try NetworkListener(using: .parameters(initialParameters: loopback) {
            WebSocket { TCP() }.autoReplyPing(false)
        })
        let (ports, ready) = AsyncStream<UInt16>.makeStream()
        _ = listener.onStateUpdate { listener, state in
            switch state {
            case .ready: if let port = listener.port { ready.yield(port.rawValue) }
            case .failed, .cancelled: ready.finish()
            default: break
            }
        }
        let (pings, received) = AsyncStream<Void>.makeStream()
        self.pings = pings
        listening = Task {
            try await listener.run { connection in
                while true {
                    let message = try await connection.receive()
                    if message.metadata.opcode == .ping { received.yield(()) }
                }
            }
        }
        var readiness = ports.makeAsyncIterator()
        guard let port = await readiness.next() else {
            listening.cancel()
            throw URLError(.cannotConnectToHost)
        }
        endpoint = URL(string: "ws://127.0.0.1:\(port)/")!
    }

    /// Closes the listener and every connection.
    func stop() { listening.cancel() }
}
