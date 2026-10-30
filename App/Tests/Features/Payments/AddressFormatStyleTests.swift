import Testing
import Transactions
@testable import widgets

struct AddressFormatStyleTests {
    @Test func `An address shortens to its ends`() throws {
        let address = try Address("6d8tEyrqPqVbEr6Jpuc7BEyYekeMUTyzHEwdmcAYEmtK")
        #expect(address.formatted(.shortAddress) == "6d8t…EmtK")
    }

    @Test func `Addresses that differ in the middle shorten the same`() throws {
        let original = try Address("6d8tEyrqPqVbEr6Jpuc7BEyYekeMUTyzHEwdmcAYEmtK")
        let lookAlike = try Address("6d8tEyrqPq1bEr6Jpuc7BEyYekeMUTyzHEwdmcAYEmtK")
        #expect(original.formatted(.shortAddress) == lookAlike.formatted(.shortAddress))
    }
}
