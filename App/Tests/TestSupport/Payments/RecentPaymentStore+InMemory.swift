import RPC
@testable import widgets

extension RecentPaymentStore {
    static func inMemory(_ storage: StoredValue<[Network: [RecentPayment]]> = StoredValue()) -> RecentPaymentStore {
        RecentPaymentStore(storage: storage)
    }
}
