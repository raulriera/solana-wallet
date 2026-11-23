import Testing
import Transactions
@testable import widgets

struct AddressFormatStyleTests {
    @Test(arguments: [(AddressFormatStyle.shortAddress, "6d8t…EmtK"), (.monogram, "6D")])
    func `An address shortens to its ends or abbreviates to its first two characters`(
        style: AddressFormatStyle, formatted: String
    ) throws {
        #expect(try Address("6d8tEyrqPqVbEr6Jpuc7BEyYekeMUTyzHEwdmcAYEmtK").formatted(style) == formatted)
    }
}
