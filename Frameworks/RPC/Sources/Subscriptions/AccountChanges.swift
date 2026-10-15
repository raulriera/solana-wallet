/// Finalized account subscriptions whose notifications coalesce into increasing change slots.
struct AccountChanges: SubscriptionGroup {
    let requests: [SubscriptionRequest]
    private var latestSlot: UInt64?

    /// Creates one finalized subscription per account.
    /// - Parameter addresses: The accounts to watch; a repeated address is watched once.
    init(addresses: [String]) {
        // Providers either reuse one subscription for a repeated account or notify it twice, so send each once.
        requests = addresses.uniqued().map { address in
            SubscriptionRequest(method: "accountSubscribe",
                                params: [address, LedgerConfiguration(includesAccountData: true)],
                                notification: "accountNotification")
        }
    }

    /// Keeps only the newest unread slot, since each slot asks the consumer to reconcile every account.
    var bufferingPolicy: AsyncThrowingStream<UInt64, any Error>.Continuation.BufferingPolicy { .bufferingNewest(1) }

    /// Turns a notification into its finalized slot when that slot is newer than every earlier one.
    /// - Parameter notification: A notification for one of the accounts.
    /// - Returns: The newer change slot, or `nil` for a duplicate or older event.
    /// - Throws: A decoding error when the notification has no slot.
    mutating func event(for notification: SubscriptionNotification) throws -> UInt64? {
        let slot = try notification.result(Change.self).context.slot
        if let latestSlot, slot <= latestSlot { return nil }
        latestSlot = slot
        return slot
    }

    /// The part of an account notification's result that carries its slot.
    private struct Change: Decodable {
        let context: Context
    }
}

extension SubscriptionGroup where Self == AccountChanges {
    /// Finalized subscriptions to accounts whose notifications coalesce into increasing change slots.
    /// - Parameter addresses: The accounts to watch; a repeated address is watched once.
    /// - Returns: One subscription per account.
    static func accountChanges(for addresses: [String]) -> AccountChanges {
        AccountChanges(addresses: addresses)
    }
}
