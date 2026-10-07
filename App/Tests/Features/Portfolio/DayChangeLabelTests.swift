import Foundation
import Testing
@testable import widgets

/// Checks the size that the 24-hour change label shows.
@MainActor
struct DayChangeLabelTests {
    /// Visible moves round to the two percentage decimals the label shows.
    /// - Parameters:
    ///   - change: The 24-hour change as a fraction.
    ///   - shown: The change the label shows.
    @Test(arguments: [
        (Decimal(string: "0.0129")!, Decimal(string: "0.0129")!),
        (Decimal(string: "-0.034749")!, Decimal(string: "-0.0347")!),
        (Decimal(string: "-0.00005")!, Decimal(string: "-0.0001")!),
    ])
    func `Visible moves round to two percentage decimals`(change: Decimal, shown: Decimal) {
        #expect(DayChangeLabel(change: change).shownChange == shown)
    }

    /// Moves smaller than 0.01% show as unchanged, with no arrow pointing up or down.
    /// - Parameter change: A 24-hour change too small to show.
    @Test(arguments: [Decimal(string: "-0.0000088")!, Decimal(string: "0.00004999")!])
    func `Moves too small to show read as unchanged`(change: Decimal) {
        #expect(DayChangeLabel(change: change).shownChange == 0)
    }
}
