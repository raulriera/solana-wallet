/// A finalized subscription to one signature and a subscription to new roots.
struct SignatureWatch: SubscriptionGroup {
    let requests: [SubscriptionRequest]
    private var latestRoot: UInt64?

    /// Creates the signature subscription, followed by the root subscription.
    ///
    /// - Parameter signature: The base-58 encoded signature of a sent transaction.
    init(signature: String) {
        requests = [
            SubscriptionRequest(method: "signatureSubscribe", params: [signature, LedgerConfiguration()],
                                notification: "signatureNotification"),
            SubscriptionRequest(method: "rootSubscribe", params: [], notification: "rootNotification"),
        ]
    }

    var bufferingPolicy: AsyncThrowingStream<SignatureEvent, any Error>.Continuation.BufferingPolicy { .unbounded }

    mutating func event(for notification: SubscriptionNotification) throws -> SignatureEvent? {
        if notification.request.method == "signatureSubscribe" {
            let landing = try notification.result(Landing.self)
            return .landed(slot: landing.context.slot, error: landing.value.error)
        }
        let root = try notification.result(UInt64.self)
        if let latestRoot, root <= latestRoot { return nil }
        latestRoot = root
        return .rooted(root)
    }

    /// The parts of a signature notification's result that carry its slot and the execution result.
    private struct Landing: Decodable {
        let context: Context
        let value: Execution
    }

    /// A landed transaction's execution result.
    private struct Execution: Decodable {
        /// The execution error, or `nil` after success.
        let error: TransactionError?

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
    /// Creates a finalized subscription to a signature and a subscription to new roots.
    ///
    /// - Parameter signature: The base-58 encoded signature of a sent transaction.
    /// - Returns: The signature subscription, followed by the root subscription.
    static func signatureWatch(for signature: String) -> SignatureWatch {
        SignatureWatch(signature: signature)
    }
}
