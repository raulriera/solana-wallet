import Testing
import Transactions
@testable import widgets

struct PaymentRecipientTests {
    @Test func `A saved recipient shows its name`() throws {
        let recipient = PaymentRecipient(address: try Address("6d8tEyrqPqVbEr6Jpuc7BEyYekeMUTyzHEwdmcAYEmtK"),
                                         name: "Alice")
        #expect(recipient.title == "Alice")
    }

    @Test func `An unsaved recipient shows its short address`() throws {
        let recipient = PaymentRecipient(address: try Address("6d8tEyrqPqVbEr6Jpuc7BEyYekeMUTyzHEwdmcAYEmtK"),
                                         name: nil)
        #expect(recipient.title == "6d8t…EmtK")
    }

    @Test(arguments: [("Alice" as String?, "6d8t…EmtK"), (nil, "")])
    func `Only a saved recipient shows its address under the name`(name: String?, subtitle: String) throws {
        let recipient = PaymentRecipient(address: try Address("6d8tEyrqPqVbEr6Jpuc7BEyYekeMUTyzHEwdmcAYEmtK"),
                                         name: name)
        #expect(recipient.subtitle == subtitle)
    }
}
