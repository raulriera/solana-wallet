import Foundation

/// The acknowledgment and routing state of one connection's subscriptions.
struct SubscriptionState<Group: SubscriptionGroup>: Sendable {
    /// The requests to send, in order.
    let requests: [SubscriptionRequest]
    private var group: Group
    private var pending: [String: SubscriptionRequest]
    private var subscriptions: [UInt64: SubscriptionRequest] = [:]

    /// Creates a state that awaits an acknowledgment for each of the group's requests.
    ///
    /// - Parameter group: The connection's subscriptions.
    init(group: Group) {
        self.group = group
        requests = group.requests
        pending = Dictionary(uniqueKeysWithValues: requests.map { ($0.id, $0) })
    }

    /// Whether the server has acknowledged every subscription request.
    var isAcknowledged: Bool { pending.isEmpty }

    /// Validates one message and turns a notification into the group's event.
    ///
    /// - Parameters:
    ///   - data: The received JSON bytes.
    ///   - redactor: The redactor that removes secrets from server messages.
    /// - Returns: An event, or `nil` for an acknowledgment or a notification without a new event.
    /// - Throws: An ``RPCError`` or a decoding error.
    mutating func accept(_ data: Data, redactor: any TextRedactor) throws -> Group.Event? {
        let decoder = JSONDecoder()
        let header = try decoder.decode(Header.self, from: data)
        guard header.jsonrpc == "2.0" else { throw RPCError.invalidResponse(.unsupportedVersion) }
        if let method = header.method {
            let route = try decoder.decode(Route.self, from: data)
            guard let request = subscriptions[route.params.subscription], method == request.notification else {
                throw RPCError.invalidResponse(.mismatchedID)
            }
            return try group.event(for: SubscriptionNotification(request: request, data: data))
        }
        let response = try decoder.decode(JSONRPCResponse<UInt64>.self, from: data)
        if let id = response.id, pending[id] == nil { throw RPCError.invalidResponse(.mismatchedID) }
        switch response.result {
        case .failure(let error): throw RPCError.server(code: error.code, message: redactor.redact(error.message))
        case .success(let subscription):
            guard let id = response.id, let request = pending.removeValue(forKey: id),
                  subscriptions.updateValue(request, forKey: subscription) == nil else {
                throw RPCError.invalidResponse(.mismatchedID)
            }
            return nil
        }
    }

    /// The routing fields common to subscription messages.
    private struct Header: Decodable { let jsonrpc: String; let method: String? }
    /// The notification fields that name its subscription.
    private struct Route: Decodable {
        let params: Parameters
        /// The notification parameters that hold its subscription ID.
        struct Parameters: Decodable { let subscription: UInt64 }
    }
}
