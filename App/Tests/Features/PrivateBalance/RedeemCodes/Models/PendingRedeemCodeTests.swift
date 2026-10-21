import Foundation
import Testing
@testable import widgets

/// Verifies when a prepared code's pending index expires, and that it round trips.
struct PendingRedeemCodeTests {
    /// The date when the fixture code was prepared.
    private static let created = Date(timeIntervalSince1970: 1_000_000)

    /// A pending index stays for an hour after its preparation, while its funding could still land, and expires after.
    /// - Parameters:
    ///   - elapsed: The seconds since the code was prepared.
    ///   - isExpired: Whether the index is expired then.
    @Test(arguments: [(0, false), (3_600, false), (3_601, true)] as [(TimeInterval, Bool)])
    func `Pending indices expire after an hour`(elapsed: TimeInterval, isExpired: Bool) {
        let code = PendingRedeemCode(index: 4, created: Self.created)

        #expect(code.isExpired(at: Self.created.addingTimeInterval(elapsed)) == isExpired)
    }

    /// A pending index decodes to the same index and date.
    @Test
    func `Pending indices round trip`() throws {
        let code = PendingRedeemCode(index: 4, created: Self.created)

        #expect(try JSONDecoder().decode(PendingRedeemCode.self, from: JSONEncoder().encode(code)) == code)
    }
}
