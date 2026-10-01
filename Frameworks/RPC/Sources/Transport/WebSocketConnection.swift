import Foundation

/// The message transport used by a subscription session.
protocol WebSocketConnection: Sendable {
    /// Sends one UTF-8 JSON message.
    /// - Parameter data: The encoded message.
    /// - Throws: A transport error.
    func send(_ data: Data) async throws
    /// Receives the next text or binary JSON message.
    /// - Returns: The message bytes.
    /// - Throws: A transport or connection-closure error.
    func receive() async throws -> Data
    /// Checks that the connection remains responsive.
    /// - Throws: A transport error if the ping fails.
    func ping() async throws
    /// Closes the connection and cancels pending transport operations.
    func cancel()
}

/// An ephemeral URLSession WebSocket whose cancellation releases the entire session.
final class URLSessionSocket: WebSocketConnection {
    private let session: URLSession
    private let task: URLSessionWebSocketTask

    /// Opens one socket without storing authentication outside its session.
    /// - Parameter endpoint: The provider's authenticated WebSocket URL.
    init(endpoint: URL) {
        session = URLSession(configuration: .ephemeral)
        task = session.webSocketTask(with: URLRequest(url: endpoint, timeoutInterval: 30))
        task.maximumMessageSize = 1_048_576
        task.resume()
    }

    /// Sends an encoded JSON message as WebSocket text.
    /// - Parameter data: UTF-8 JSON bytes.
    /// - Throws: A transport or HTTP upgrade error.
    func send(_ data: Data) async throws {
        do { try await task.send(.string(String(decoding: data, as: UTF8.self))) }
        catch { throw failure(error) }
    }

    /// Receives a message without exposing provider response bodies in errors.
    /// - Returns: UTF-8 text or binary message bytes.
    /// - Throws: A transport or HTTP upgrade error.
    func receive() async throws -> Data {
        do {
            switch try await task.receive() {
            case .data(let data): return data
            case .string(let string): return Data(string.utf8)
            @unknown default: throw RPCError.decoding
            }
        } catch { throw failure(error) }
    }

    /// Sends a WebSocket ping and awaits its pong.
    /// - Throws: The transport failure reported by URLSession.
    func ping() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            task.sendPing { error in
                if let error { continuation.resume(throwing: self.failure(error)) }
                else { continuation.resume() }
            }
        }
    }

    /// Cancels transport operations and releases all server subscriptions by closing the socket.
    func cancel() {
        task.cancel(with: .goingAway, reason: nil)
        session.invalidateAndCancel()
    }

    /// Preserves HTTP upgrade failures for sanitization by the subscription client.
    /// - Parameter error: The URLSession error.
    /// - Returns: An HTTP status error when available, otherwise the original transport error.
    private func failure(_ error: any Error) -> any Error {
        if let response = task.response as? HTTPURLResponse, response.statusCode != 101,
           !(200..<300).contains(response.statusCode) {
            return RPCError.http(statusCode: response.statusCode,
                                 retryAfter: response.value(forHTTPHeaderField: "Retry-After"))
        }
        return error
    }
}
