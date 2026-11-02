import Foundation
import Synchronization

/// A type that performs an HTTP request and returns its response data.
protocol HTTPTransport: Sendable {
    /// Performs a request and returns its response data.
    ///
    /// - Parameter request: The request to perform.
    /// - Returns: The response body and metadata.
    /// - Throws: A transport error.
    func data(for request: URLRequest) async throws -> (Data, URLResponse)

    /// Performs a request and returns its response data, refusing a body longer than a limit.
    ///
    /// - Parameters:
    ///   - request: The request to perform.
    ///   - maximumLength: The longest body, in bytes, to accept.
    /// - Returns: The response body and metadata.
    /// - Throws: ``RPCError/InvalidResponse/oversized`` for a longer body, or a transport error.
    func data(for request: URLRequest, maximumLength: Int) async throws -> (Data, URLResponse)
}

extension HTTPTransport {
    /// Performs a request, then refuses its response data if the body is longer than a limit.
    ///
    /// - Parameters:
    ///   - request: The request to perform.
    ///   - maximumLength: The longest body, in bytes, to accept.
    /// - Returns: The response body and metadata.
    /// - Throws: ``RPCError/InvalidResponse/oversized`` for a longer body, or a transport error.
    func data(for request: URLRequest, maximumLength: Int) async throws -> (Data, URLResponse) {
        let (data, response) = try await data(for: request)
        guard data.count <= maximumLength else { throw RPCError.invalidResponse(.oversized) }
        return (data, response)
    }
}

/// An HTTP transport backed by a URL session.
struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    /// Creates a transport with a session for a configuration that fails each request after a time limit.
    ///
    /// - Parameters:
    ///   - configuration: The session's configuration, whose resource timeout the transport sets.
    ///   - resourceTimeout: The longest time, in seconds, that a request and its whole response may take.
    init(configuration: URLSessionConfiguration = .ephemeral, resourceTimeout: TimeInterval = 300) {
        configuration.timeoutIntervalForResource = resourceTimeout
        session = URLSession(configuration: configuration)
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }

    /// Performs a request and collects its body in chunks until it ends or grows longer than a limit.
    ///
    /// - Parameters:
    ///   - request: The request to perform.
    ///   - maximumLength: The longest body, in bytes, to accept.
    /// - Returns: The response body and metadata.
    /// - Throws: ``RPCError/InvalidResponse/oversized`` for a declared or read body longer than the limit, or a
    ///   transport error.
    func data(for request: URLRequest, maximumLength: Int) async throws -> (Data, URLResponse) {
        let reader = BoundedBodyReader(maximumLength: maximumLength)
        let task = session.dataTask(with: request)
        task.delegate = reader
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                reader.start(task, continuation: continuation)
            }
        } onCancel: {
            task.cancel()
        }
    }
}

/// A data task delegate that collects a response body and cancels the task once the body grows longer than a limit.
private final class BoundedBodyReader: NSObject, URLSessionDataDelegate, Sendable {
    /// The body collected so far, whether it grew longer than the limit, and the caller waiting for the task.
    private struct State {
        var body = Data()
        var isOversized = false
        var continuation: CheckedContinuation<(Data, URLResponse), any Error>?
    }

    private let maximumLength: Int
    private let state = Mutex(State())

    /// Creates a reader that refuses a body longer than a limit.
    ///
    /// - Parameter maximumLength: The longest body, in bytes, to accept.
    init(maximumLength: Int) {
        self.maximumLength = maximumLength
    }

    /// Starts a task whose delegate is this reader and resumes a continuation once the task finishes.
    ///
    /// - Parameters:
    ///   - task: The data task to start.
    ///   - continuation: The continuation that receives the body and response, or the error that ended the task.
    func start(_ task: URLSessionDataTask, continuation: CheckedContinuation<(Data, URLResponse), any Error>) {
        state.withLock { $0.continuation = continuation }
        task.resume()
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
    ) {
        guard response.expectedContentLength <= maximumLength else {
            state.withLock { $0.isOversized = true }
            completionHandler(.cancel)
            return
        }
        state.withLock { $0.body.reserveCapacity(Int(max(response.expectedContentLength, 0))) }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let isOversized = state.withLock { state in
            guard !state.isOversized, state.body.count + data.count <= maximumLength else {
                state.isOversized = true
                return true
            }
            state.body.append(data)
            return false
        }
        if isOversized { dataTask.cancel() }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        let (continuation, result) = state.withLock { state in
            defer { state.continuation = nil }
            let result: Result<(Data, URLResponse), any Error>
            if state.isOversized {
                result = .failure(RPCError.invalidResponse(.oversized))
            } else if let error {
                result = .failure(error)
            } else if let response = task.response {
                result = .success((state.body, response))
            } else {
                result = .failure(URLError(.badServerResponse))
            }
            return (state.continuation, result)
        }
        continuation?.resume(with: result)
    }
}
