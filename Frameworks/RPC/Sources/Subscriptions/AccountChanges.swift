/// Finalized account subscriptions whose notifications coalesce into increasing change slots.
struct AccountChanges: SubscriptionGroup {
    let requests: [SubscriptionRequest]
    private var latestSlot: UInt64?

    /// Creates one finalized subscription per account.
    ///
    /// - Parameter addresses: The accounts to watch.
    init(addresses: [String]) {
        requests = addresses.uniqued().map { address in
            SubscriptionRequest(method: "accountSubscribe",
                                params: [address, LedgerConfiguration(includesAccountData: true)],
                                notification: "accountNotification")
        }
    }

    var bufferingPolicy: AsyncThrowingStream<UInt64, any Error>.Continuation.BufferingPolicy { .bufferingNewest(1) }

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
    /// Creates finalized subscriptions whose notifications coalesce into increasing change slots.
    ///
    /// - Parameter addresses: The accounts to watch.
    /// - Returns: One subscription per account.
    static func accountChanges(for addresses: [String]) -> AccountChanges {
        AccountChanges(addresses: addresses)
    }
}
