import RPC

nonisolated extension RPCError {
    /// Whether a keyed provider refused the request's API key: HTTP status 401 or 403.
    var rejectsKey: Bool {
        switch self {
        case .http(statusCode: 401, retryAfter: _), .http(statusCode: 403, retryAfter: _): true
        default: false
        }
    }
}
