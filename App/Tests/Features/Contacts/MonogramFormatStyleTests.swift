import Foundation
import Testing
import Transactions
@testable import widgets

struct MonogramFormatStyleTests {
    @Test(arguments: [("Adam Okon" as String?, "AO"), ("Account 12", "A12"), ("Rent 2024", "R"), (nil, "6D")])
    func `A recipient abbreviates to its name's initials and trailing number, or else to its address`(
        name: String?, monogram: String
    ) throws {
        let recipient = PaymentRecipient(address: try Address("6d8tEyrqPqVbEr6Jpuc7BEyYekeMUTyzHEwdmcAYEmtK"),
                                         name: name)
        #expect(MonogramFormatStyle.monogram.locale(Locale(identifier: "en_US")).format(recipient) == monogram)
    }
}
