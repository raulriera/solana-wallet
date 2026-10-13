import Foundation
import Synchronization
@testable import RPC

/// Opens a new local socket for each subscription connection, so a test can follow reconnections.
final class SocketSequence: Sendable {
    /// Produces the responder for a connection from its zero-based position.
    typealias Script = @Sendable (Int) -> SocketFixture.Responder

    /// The connections in the order they open.
    let openings: AsyncStream<SocketFixture>
    private let opened: AsyncStream<SocketFixture>.Continuation
    private let script: Script
    private let state = Mutex<[SocketFixture]>([])

    /// Creates connections that each follow their script.
    /// - Parameter script: The responder for each connection; by default, each one acknowledges a signature watch.
    init(_ script: @escaping Script = { _ in SocketSequence.watch() }) {
        (openings, opened) = AsyncStream.makeStream()
        self.script = script
    }

    /// The connections opened so far, in order.
    var sockets: [SocketFixture] { state.withLock(\.self) }

    /// Opens the next connection with its script.
    /// - Parameter endpoint: The provider's subscription URL.
    /// - Returns: A local connection that never reaches the network.
    func connect(_ endpoint: URL) -> any WebSocketConnection {
        let socket = state.withLock { sockets in
            let socket = SocketFixture(respond: script(sockets.count))
            sockets.append(socket)
            return socket
        }
        opened.yield(socket)
        return socket
    }

    /// Waits until every connection opened so far is closed.
    func waitUntilClosed() async {
        for socket in sockets { await socket.waitUntilCancelled() }
    }

    /// Acknowledges a signature watch's two subscriptions, then delivers notifications.
    /// - Parameter notifications: The frames that follow the root subscription's acknowledgment.
    /// - Returns: A responder for one connection.
    static func watch(then notifications: [Data] = []) -> SocketFixture.Responder {
        { request, ordinal in
            let acknowledgment = try SocketFixture.acknowledgment(of: request, ordinal: ordinal)
            return ordinal == 2 ? [acknowledgment] + notifications : [acknowledgment]
        }
    }

    /// Fails a connection's first subscription request, as a connection that can't open does.
    /// - Parameter error: The error that sending the request throws.
    /// - Returns: A responder for one connection.
    static func failing(with error: any Error) -> SocketFixture.Responder {
        { _, _ in throw error }
    }
}
