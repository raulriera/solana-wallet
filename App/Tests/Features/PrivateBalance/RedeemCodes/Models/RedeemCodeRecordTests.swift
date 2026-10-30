import Foundation
import Testing
@testable import widgets

struct RedeemCodeRecordTests {
    @Test
    func `Records round trip`() throws {
        let record = RedeemCodeRecord(index: 7, amount: 2_000_000, reserve: 1_340_068,
                                      created: Date(timeIntervalSince1970: 1_800_000_000), fundingSignature: "funding")

        #expect(try JSONDecoder().decode(RedeemCodeRecord.self, from: JSONEncoder().encode(record)) == record)
    }
}
