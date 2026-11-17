import Testing
import Transactions
@testable import widgets

struct PaymentRecipientTests {
    @Test(arguments: [("Alice" as String?, "Alice", "6d8t…EmtK"), (nil, "6d8t…EmtK", "")])
    func `A saved recipient shows its name over its address and an unsaved one its short address`(
        name: String?, title: String, subtitle: String
    ) throws {
        let recipient = PaymentRecipient(address: try Address("6d8tEyrqPqVbEr6Jpuc7BEyYekeMUTyzHEwdmcAYEmtK"),
                                         name: name)
        #expect(recipient.title == title)
        #expect(recipient.subtitle == subtitle)
    }
}
