import Foundation
import Testing
@testable import widgets

struct PendingRedeemCodeTests {
    private static let created = Date(timeIntervalSince1970: 1_000_000)

    @Test(arguments: [(3_600, false), (3_601, true)] as [(TimeInterval, Bool)])
    func `Pending indices expire after an hour`(elapsed: TimeInterval, isExpired: Bool) {
        let code = PendingRedeemCode(index: 4, created: Self.created)

        #expect(code.isExpired(at: Self.created.addingTimeInterval(elapsed)) == isExpired)
    }
}
