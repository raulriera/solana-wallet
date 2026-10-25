import Testing
import Transactions
@testable import widgets

/// Checks how a recipient is titled.
struct PaymentRecipientTests {
    /// A saved recipient is titled by name.
    @Test func `A saved recipient shows its name`() throws {
        let recipient = PaymentRecipient(address: try Address("6d8tEyrqPqVbEr6Jpuc7BEyYekeMUTyzHEwdmcAYEmtK"),
                                         name: "Alice")
        #expect(recipient.title == "Alice")
    }

    /// An unsaved recipient is titled by its shortened address.
    @Test func `An unsaved recipient shows its short address`() throws {
        let recipient = PaymentRecipient(address: try Address("6d8tEyrqPqVbEr6Jpuc7BEyYekeMUTyzHEwdmcAYEmtK"),
                                         name: nil)
        #expect(recipient.title == "6d8t…EmtK")
    }

    /// A saved recipient shows its short address under its name; an unsaved one shows nothing more, since its title
    /// is already the short address.
    /// - Parameters:
    ///   - name: The name the address is saved under, if any.
    ///   - subtitle: The line under the title.
    @Test(arguments: [("Alice" as String?, "6d8t…EmtK"), (nil, "")])
    func `Only a saved recipient shows its address under the name`(name: String?, subtitle: String) throws {
        let recipient = PaymentRecipient(address: try Address("6d8tEyrqPqVbEr6Jpuc7BEyYekeMUTyzHEwdmcAYEmtK"),
                                         name: name)
        #expect(recipient.subtitle == subtitle)
    }
}
