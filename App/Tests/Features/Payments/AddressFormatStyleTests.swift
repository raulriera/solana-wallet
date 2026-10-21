import Testing
import Transactions
@testable import widgets

/// Checks that addresses shorten to their first and last four characters.
struct AddressFormatStyleTests {
    /// A shortened address keeps its first and last four characters around an ellipsis.
    @Test func `An address shortens to its ends`() throws {
        let address = try Address("6d8tEyrqPqVbEr6Jpuc7BEyYekeMUTyzHEwdmcAYEmtK")
        #expect(address.formatted(.shortAddress) == "6d8t…EmtK")
    }

    /// Addresses that differ only in the middle shorten the same, which is what address poisoning relies on.
    @Test func `Addresses that differ in the middle shorten the same`() throws {
        let original = try Address("6d8tEyrqPqVbEr6Jpuc7BEyYekeMUTyzHEwdmcAYEmtK")
        let lookAlike = try Address("6d8tEyrqPq1bEr6Jpuc7BEyYekeMUTyzHEwdmcAYEmtK")
        #expect(original.formatted(.shortAddress) == lookAlike.formatted(.shortAddress))
    }
}
