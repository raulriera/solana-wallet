import Foundation

/// A connection that exchanges JSON messages over a WebSocket.
protocol WebSocketConnection: Sendable {
    /// Sends one UTF-8 JSON message.
    ///
    /// - Parameter data: The encoded message.
    /// - Throws: A transport error.
    func send(_ data: Data) async throws
    /// Receives the next text or binary JSON message.
    ///
    /// - Returns: The message bytes.
    /// - Throws: A transport or connection-closure error.
    func receive() async throws -> Data
    /// Checks that the connection remains responsive.
    ///
    /// - Throws: A transport error or `CancellationError`.
    func ping() async throws
    /// Closes the connection and cancels pending transport operations.
    func cancel()
}

/// A WebSocket connection backed by an ephemeral URL session.
final class URLSessionSocket: WebSocketConnection {
    private let session: URLSession
    private let task: URLSessionWebSocketTask

    /// Opens a socket to an endpoint.
    ///
    /// - Parameter endpoint: The WebSocket URL.
    init(endpoint: URL) {
        session = URLSession(configuration: .ephemeral)
        task = session.webSocketTask(with: URLRequest(url: endpoint, timeoutInterval: 30))
        task.maximumMessageSize = 1_048_576
        task.resume()
    }

    func send(_ data: Data) async throws {
        do { try await task.send(.string(String(decoding: data, as: UTF8.self))) }
        catch { throw upgradeError(error) }
    }

    func receive() async throws -> Data {
        do {
            switch try await task.receive() {
            case .data(let data): return data
            case .string(let string): return Data(string.utf8)
            @unknown default: throw RPCError.decoding
            }
        } catch { throw upgradeError(error) }
    }

    func ping() async throws {
        try Task.checkCancellation()
        let (pong, received) = AsyncThrowingStream<Void, any Error>.makeStream()
        task.sendPing { error in received.finish(throwing: error.map(self.upgradeError)) }
        for try await _ in pong {}
        try Task.checkCancellation()
    }

    func cancel() {
        task.cancel(with: .goingAway, reason: nil)
        session.invalidateAndCancel()
    }

    /// Returns the HTTP status error of a failed upgrade, or the original error.
    ///
    /// - Parameter error: The URL session error.
    /// - Returns: An HTTP status error when available, otherwise `error`.
    private func upgradeError(_ error: any Error) -> any Error {
        if let response = task.response as? HTTPURLResponse, response.statusCode != 101,
           let statusError = RPCError(response: response) {
            return statusError
        }
        return error
    }
}
