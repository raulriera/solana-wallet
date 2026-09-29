import Foundation

/// Validates acknowledgments and notifications for exactly one wallet's subscriptions.
struct SubscriptionState: Sendable {
    var pending: [String: String]
    private var subscriptions: [UInt64: String] = [:]
    private(set) var latestSlot: UInt64?

    /// Creates a decoder for the outstanding request IDs and their expected notification methods.
    /// - Parameter pending: Request IDs mapped to their notification method names.
    init(pending: [String: String]) { self.pending = pending }

    /// Validates one message and coalesces notifications into increasing confirmed slots.
    /// - Parameters:
    ///   - data: The received JSON bytes.
    ///   - redactor: The provider's diagnostic redaction policy.
    /// - Returns: A newer change slot, or `nil` for an acknowledgment or duplicate event.
    /// - Throws: A server, decoding, or envelope-validation error.
    mutating func accept(_ data: Data, redactor: any TextRedactor) throws -> UInt64? {
        let decoder = JSONDecoder()
        let header = try decoder.decode(Header.self, from: data)
        guard header.jsonrpc == "2.0" else { throw RPCError.invalidResponse(.unsupportedVersion) }
        if let method = header.method {
            let notification = try decoder.decode(Notification.self, from: data)
            guard subscriptions[notification.params.subscription] == method else {
                throw RPCError.invalidResponse(.mismatchedID)
            }
            let slot = notification.params.result.context.slot
            guard latestSlot == nil || slot > latestSlot! else { return nil }
            latestSlot = slot
            return slot
        }
        let response = try decoder.decode(JSONRPCResponse<UInt64>.self, from: data)
        if let id = response.id, pending[id] == nil { throw RPCError.invalidResponse(.mismatchedID) }
        switch response.result {
        case .failure(let error): throw RPCError.server(code: error.code, message: redactor.redact(error.message))
        case .success(let subscription):
            guard let id = response.id, let method = pending.removeValue(forKey: id), subscriptions[subscription] == nil else {
                throw RPCError.invalidResponse(.mismatchedID)
            }
            subscriptions[subscription] = method
            return nil
        }
    }

    /// The routing fields common to subscription messages.
    private struct Header: Decodable { let jsonrpc: String; let method: String? }
    /// A notification's validated routing metadata and indexing signal.
    private struct Notification: Decodable {
        let params: Parameters
        struct Parameters: Decodable { let subscription: UInt64; let result: Result }
        struct Result: Decodable { let context: SlotContext }
        struct SlotContext: Decodable { let slot: UInt64 }
    }
}
