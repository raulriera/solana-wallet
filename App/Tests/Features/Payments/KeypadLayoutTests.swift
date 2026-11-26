import SwiftUI
import Testing
@testable import widgets

struct KeypadLayoutTests {
    private static let count = 12

    @Test(arguments: [
        (ProposedViewSize.unspecified, 12, CGSize(width: 270, height: 370)),
        (.infinity, 12, CGSize(width: 270, height: 370)),
        (ProposedViewSize(width: 1000, height: 1000), 12, CGSize(width: 270, height: 370)),
        (ProposedViewSize(width: 270, height: 370), 12, CGSize(width: 270, height: 370)),
        (ProposedViewSize(width: 400, height: 185), 12, CGSize(width: 135, height: 185)),
        (ProposedViewSize(width: 135, height: nil), 12, CGSize(width: 135, height: 185)),
        (.zero, 12, .zero),
        (.unspecified, 0, .zero),
        (.unspecified, 1, CGSize(width: 270, height: 106)),
        (.unspecified, 10, CGSize(width: 270, height: 370)),
    ] as [(ProposedViewSize, Int, CGSize)])
    func `The keypad takes whole rows for its keys at the largest size that fits`(
        proposal: ProposedViewSize, count: Int, size: CGSize
    ) {
        #expect(KeypadLayout.size(fitting: proposal, count: count) == size)
    }

    @Test func `Scaled down keys keep their gaps and margins in proportion`() {
        let bounds = CGRect(x: 0, y: 0, width: 135, height: 185)

        #expect(KeypadLayout.frame(ofKeyAt: 0, count: Self.count, in: bounds) == CGRect(x: 0, y: 9, width: 35,
                                                                                        height: 35))
        #expect(KeypadLayout.frame(ofKeyAt: 4, count: Self.count, in: bounds) == CGRect(x: 50, y: 53, width: 35,
                                                                                        height: 35))
        #expect(KeypadLayout.frame(ofKeyAt: 11, count: Self.count, in: bounds) == CGRect(x: 100, y: 141, width: 35,
                                                                                         height: 35))
    }

    @Test func `Keys sit centered in bounds larger than the keypad`() {
        let bounds = CGRect(x: 10, y: 20, width: 400, height: 600)

        #expect(KeypadLayout.frame(ofKeyAt: 0, count: Self.count, in: bounds) == CGRect(x: 75, y: 153, width: 70,
                                                                                        height: 70))
        #expect(KeypadLayout.frame(ofKeyAt: 11, count: Self.count, in: bounds) == CGRect(x: 275, y: 417, width: 70,
                                                                                         height: 70))
    }

    @Test(arguments: [
        (CGSize(width: 270, height: 370), CGFloat(18)),
        (CGSize(width: 135, height: 185), CGFloat(9)),
    ])
    func `The gap between rows scales with the keys`(size: CGSize, gap: CGFloat) {
        #expect(KeypadLayout.rowGap(inKeypadOf: size, count: Self.count) == gap)
    }
}
