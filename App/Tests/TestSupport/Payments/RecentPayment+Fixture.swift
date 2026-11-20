import Foundation
import Transactions
@testable import widgets

extension RecentPayment {
    static func fixture(to address: Address, at seconds: TimeInterval = 0) -> RecentPayment {
        RecentPayment(address: address, date: Date(timeIntervalSinceReferenceDate: seconds))
    }
}
