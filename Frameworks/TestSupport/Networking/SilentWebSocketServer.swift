import Foundation
import Network

final class SilentWebSocketServer: Sendable {
    let endpoint: URL
    let pings: AsyncStream<Void>
    private let listening: Task<Void, any Error>

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
        // swift-format-ignore: NeverForceUnwrap
        endpoint = URL(string: "ws://127.0.0.1:\(port)/")!
    }

    func stop() { listening.cancel() }
}
