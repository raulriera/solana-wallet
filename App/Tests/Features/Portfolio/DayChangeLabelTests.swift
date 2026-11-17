import Foundation
import Testing
@testable import widgets

@MainActor
struct DayChangeLabelTests {
    @Test(arguments: [
        (Decimal(string: "0.0129")!, Decimal(string: "0.0129")!),
        (Decimal(string: "-0.034749")!, Decimal(string: "-0.0347")!),
        (Decimal(string: "-0.00005")!, Decimal(string: "-0.0001")!),
        (Decimal(string: "-0.0000088")!, 0),
        (Decimal(string: "0.00004999")!, 0),
    ] as [(Decimal, Decimal)])
    func `Moves round to two percentage decimals and smaller ones read as unchanged`(change: Decimal, shown: Decimal) {
        #expect(DayChangeLabel(change: change).shownChange == shown)
    }
}
