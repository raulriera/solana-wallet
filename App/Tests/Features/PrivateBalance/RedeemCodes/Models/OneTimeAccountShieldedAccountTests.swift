import CryptoKit
import Foundation
import Privacy
import Testing
import Transactions
import Wallet
@testable import widgets

struct OneTimeAccountShieldedAccountTests {
    @Test
    func `The shielded account uses the one-time address`() throws {
        let oneTime = try OneTimeAccount(secret: SymmetricKey(data: Data(repeating: 7, count: 32)))

        let shielded = try oneTime.shieldedAccount

        #expect(shielded.signingAddress.value == oneTime.address)
        #expect(try shielded.recipient.signingAddress.value == oneTime.address)
    }
}
