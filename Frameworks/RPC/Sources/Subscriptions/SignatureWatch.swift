/// A finalized subscription to one signature and a subscription to new roots, whose notifications become signature events.
struct SignatureWatch: SubscriptionGroup {
    let requests: [SubscriptionRequest]
    private var latestRoot: UInt64?

    /// Creates the signature subscription, followed by the root subscription.
    /// - Parameter signature: The base-58 encoded signature of a sent transaction.
    init(signature: String) {
        requests = [
            SubscriptionRequest(method: "signatureSubscribe", params: [signature, LedgerConfiguration()],
                                notification: "signatureNotification"),
            SubscriptionRequest(method: "rootSubscribe", params: [], notification: "rootNotification"),
        ]
    }

    /// Keeps every unread event, so a later root never replaces the landing.
    var bufferingPolicy: AsyncThrowingStream<SignatureEvent, any Error>.Continuation.BufferingPolicy { .unbounded }

    /// Turns a signature notification into a landing, and a root notification into a root newer than every earlier one.
    /// - Parameter notification: A notification for the signature or for a new root.
    /// - Returns: The landing or the newer root, or `nil` for a duplicate or older root.
    /// - Throws: A decoding error when the notification has no execution result or no root slot.
    mutating func event(for notification: SubscriptionNotification) throws -> SignatureEvent? {
        if notification.request.method == "signatureSubscribe" {
            return .landed(error: try notification.result(Landing.self).value.error)
        }
        let root = try notification.result(UInt64.self)
        if let latestRoot, root <= latestRoot { return nil }
        latestRoot = root
        return .rooted(root)
    }

    /// The part of a signature notification's result that carries the execution result.
    private struct Landing: Decodable {
        let value: Execution
    }

    /// A landed transaction's execution result.
    private struct Execution: Decodable {
        /// The execution error, or `nil` after success.
        let error: TransactionError?

        /// Decodes the execution result while requiring its nullable error, so a malformed landing never reads as success.
        /// - Parameter decoder: The decoder containing the execution result.
        /// - Throws: A decoding error when the error field is missing or malformed.
        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            error = try container.decode(TransactionError?.self, forKey: .error)
        }

        /// The field names in an execution result.
        private enum CodingKeys: String, CodingKey {
            case error = "err"
        }
    }
}

extension SubscriptionGroup where Self == SignatureWatch {
    /// A finalized subscription to a signature and a subscription to new roots, on one connection.
    /// - Parameter signature: The base-58 encoded signature of a sent transaction.
    /// - Returns: The signature subscription, followed by the root subscription.
    static func signatureWatch(for signature: String) -> SignatureWatch {
        SignatureWatch(signature: signature)
    }
}
