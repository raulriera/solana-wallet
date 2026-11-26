import SwiftUI
import Testing
@testable import widgets

struct KeypadLayoutTests {
    private static let count = 12

    @Test(arguments: [
        (ProposedViewSize.unspecified, 12, CGSize(width: 312, height: 452)),
        (.infinity, 12, CGSize(width: 312, height: 452)),
        (ProposedViewSize(width: 1000, height: 1000), 12, CGSize(width: 312, height: 452)),
        (ProposedViewSize(width: 312, height: 452), 12, CGSize(width: 312, height: 452)),
        (ProposedViewSize(width: 400, height: 226), 12, CGSize(width: 156, height: 226)),
        (ProposedViewSize(width: 156, height: nil), 12, CGSize(width: 156, height: 226)),
        (.zero, 12, .zero),
        (.unspecified, 0, .zero),
        (.unspecified, 1, CGSize(width: 312, height: 128)),
        (.unspecified, 10, CGSize(width: 312, height: 452)),
    ] as [(ProposedViewSize, Int, CGSize)])
    func `The keypad takes whole rows for its keys at the largest size that fits`(
        proposal: ProposedViewSize, count: Int, size: CGSize
    ) {
        #expect(KeypadLayout.size(fitting: proposal, count: count) == size)
    }

    @Test func `Scaled down keys keep their gaps and margins in proportion`() {
        let bounds = CGRect(x: 0, y: 0, width: 156, height: 226)

        #expect(KeypadLayout.frame(ofKeyAt: 0, count: Self.count, in: bounds) == CGRect(x: 0, y: 10, width: 44,
                                                                                        height: 44))
        #expect(KeypadLayout.frame(ofKeyAt: 4, count: Self.count, in: bounds) == CGRect(x: 56, y: 64, width: 44,
                                                                                        height: 44))
        #expect(KeypadLayout.frame(ofKeyAt: 11, count: Self.count, in: bounds) == CGRect(x: 112, y: 172, width: 44,
                                                                                         height: 44))
    }

    @Test func `Keys sit centered in bounds larger than the keypad`() {
        let bounds = CGRect(x: 10, y: 20, width: 400, height: 600)

        #expect(KeypadLayout.frame(ofKeyAt: 0, count: Self.count, in: bounds) == CGRect(x: 54, y: 114, width: 88,
                                                                                        height: 88))
        #expect(KeypadLayout.frame(ofKeyAt: 11, count: Self.count, in: bounds) == CGRect(x: 278, y: 438, width: 88,
                                                                                         height: 88))
    }

    @Test(arguments: [
        (CGSize(width: 312, height: 452), CGFloat(20)),
        (CGSize(width: 156, height: 226), CGFloat(10)),
    ])
    func `The gap between rows scales with the keys`(size: CGSize, gap: CGFloat) {
        #expect(KeypadLayout.rowGap(inKeypadOf: size, count: Self.count) == gap)
    }
}
