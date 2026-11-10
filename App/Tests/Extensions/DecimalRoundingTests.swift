import Foundation
import Testing
@testable import widgets

struct DecimalRoundingTests {
    @Test(arguments: [
        (Decimal(string: "176.9601")!, 2, Decimal.RoundingMode.down, Decimal(string: "176.96")!),
        (Decimal(string: "0.999")!, 2, .down, Decimal(string: "0.99")!),
        (Decimal(string: "0.999")!, 2, .plain, Decimal(1)),
        (Decimal(string: "1.25")!, 0, .up, Decimal(2)),
    ])
    func `Rounding keeps the given digits after the separator`(value: Decimal, scale: Int,
                                                                mode: Decimal.RoundingMode, rounded: Decimal) {
        #expect(value.rounded(scale: scale, mode) == rounded)
    }
}
