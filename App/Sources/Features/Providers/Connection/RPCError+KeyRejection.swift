import RPC

nonisolated extension RPCError {
    /// Whether the provider refused the request's API key with HTTP status 401 or 403.
    var rejectsKey: Bool {
        switch self {
        case .http(statusCode: 401, retryAfter: _), .http(statusCode: 403, retryAfter: _): true
        default: false
        }
    }
}
