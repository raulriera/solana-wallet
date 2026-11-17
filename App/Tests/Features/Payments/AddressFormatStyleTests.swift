import Testing
import Transactions
@testable import widgets

struct AddressFormatStyleTests {
    @Test func `An address shortens to its ends`() throws {
        let address = try Address("6d8tEyrqPqVbEr6Jpuc7BEyYekeMUTyzHEwdmcAYEmtK")
        #expect(address.formatted(.shortAddress) == "6d8t…EmtK")
    }
}
