import Foundation
import Synchronization
@testable import RPC

final class SocketSequence: Sendable {
    typealias Script = @Sendable (Int) -> SocketFixture.Responder

    let openings: AsyncStream<SocketFixture>
    private let opened: AsyncStream<SocketFixture>.Continuation
    private let script: Script
    private let state = Mutex<[SocketFixture]>([])

    init(_ script: @escaping Script = { _ in SocketSequence.watch() }) {
        (openings, opened) = AsyncStream.makeStream()
        self.script = script
    }

    var sockets: [SocketFixture] { state.withLock(\.self) }

    func connect(_ endpoint: URL) -> any WebSocketConnection {
        let socket = state.withLock { sockets in
            let socket = SocketFixture(respond: script(sockets.count))
            sockets.append(socket)
            return socket
        }
        opened.yield(socket)
        return socket
    }

    func waitUntilClosed() async {
        for socket in sockets { await socket.waitUntilCancelled() }
    }

    static func watch(then notifications: [Data] = []) -> SocketFixture.Responder {
        { request, ordinal in
            let acknowledgment = try SocketFixture.acknowledgment(of: request, ordinal: ordinal)
            return ordinal == 2 ? [acknowledgment] + notifications : [acknowledgment]
        }
    }

    static func failing(with error: any Error) -> SocketFixture.Responder {
        { _, _ in throw error }
    }
}
