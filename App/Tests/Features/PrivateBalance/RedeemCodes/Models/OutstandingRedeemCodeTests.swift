import CryptoKit
import Foundation
import RPC
import Testing
@testable import widgets

/// Verifies that an outstanding code describes itself without its code or record.
struct OutstandingRedeemCodeTests {
    /// Printing, dumping, and reflecting an outstanding code omit its values.
    @Test
    func `Descriptions omit the code`() throws {
        let outstanding = OutstandingRedeemCode(
            record: RedeemCodeRecord(index: 1, amount: 2, reserve: 3, created: Date(timeIntervalSince1970: 0),
                                     fundingSignature: "funding"),
            code: try RedeemCode(secret: SymmetricKey(data: Data(1...32)), network: .devnet)
        )
        var dumped = ""
        dump(outstanding, to: &dumped)

        #expect(String(describing: outstanding) == "OutstandingRedeemCode")
        #expect(String(reflecting: outstanding) == "OutstandingRedeemCode")
        #expect(dumped == "- OutstandingRedeemCode\n")
    }
}
