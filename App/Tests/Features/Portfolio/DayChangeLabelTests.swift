import Foundation
import Testing
@testable import widgets

@MainActor
struct DayChangeLabelTests {
    @Test(arguments: [
        (Decimal(string: "0.0129")!, Decimal(string: "0.0129")!),
        (Decimal(string: "-0.034749")!, Decimal(string: "-0.0347")!),
        (Decimal(string: "-0.00005")!, Decimal(string: "-0.0001")!),
    ])
    func `Visible moves round to two percentage decimals`(change: Decimal, shown: Decimal) {
        #expect(DayChangeLabel(change: change).shownChange == shown)
    }

    @Test(arguments: [Decimal(string: "-0.0000088")!, Decimal(string: "0.00004999")!])
    func `Moves too small to show read as unchanged`(change: Decimal) {
        #expect(DayChangeLabel(change: change).shownChange == 0)
    }
}
