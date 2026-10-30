import SwiftUI
import Testing
@testable import widgets

struct KeypadLayoutTests {
    private static let count = 12

    @Test(arguments: [
        ProposedViewSize.unspecified,
        ProposedViewSize.infinity,
        ProposedViewSize(width: 1000, height: 1000),
        ProposedViewSize(width: 338, height: 456),
    ])
    func `Roomy space keeps the largest keypad`(proposal: ProposedViewSize) {
        #expect(KeypadLayout.size(fitting: proposal, count: Self.count) == CGSize(width: 338, height: 456))
    }

    @Test(arguments: [
        ProposedViewSize(width: 400, height: 228),
        ProposedViewSize(width: 169, height: nil),
    ])
    func `Space short in either dimension scales the whole keypad down`(proposal: ProposedViewSize) {
        #expect(KeypadLayout.size(fitting: proposal, count: Self.count) == CGSize(width: 169, height: 228))
    }

    @Test func `No space shrinks the keypad away`() {
        #expect(KeypadLayout.size(fitting: .zero, count: Self.count) == .zero)
    }

    @Test func `Scaled down keys keep their gaps and margins in proportion`() {
        let bounds = CGRect(x: 0, y: 0, width: 169, height: 228)

        #expect(KeypadLayout.frame(ofKeyAt: 0, count: Self.count, in: bounds) == CGRect(x: 0, y: 8, width: 47,
                                                                                        height: 47))
        #expect(KeypadLayout.frame(ofKeyAt: 4, count: Self.count, in: bounds) == CGRect(x: 61, y: 63, width: 47,
                                                                                        height: 47))
        #expect(KeypadLayout.frame(ofKeyAt: 11, count: Self.count, in: bounds) == CGRect(x: 122, y: 173, width: 47,
                                                                                         height: 47))
    }

    @Test func `Keys sit centered in bounds larger than the keypad`() {
        let bounds = CGRect(x: 10, y: 20, width: 400, height: 600)

        #expect(KeypadLayout.frame(ofKeyAt: 0, count: Self.count, in: bounds) == CGRect(x: 41, y: 108, width: 94,
                                                                                        height: 94))
        #expect(KeypadLayout.frame(ofKeyAt: 11, count: Self.count, in: bounds) == CGRect(x: 285, y: 438, width: 94,
                                                                                         height: 94))
    }

    @Test(arguments: [
        (CGSize(width: 338, height: 456), CGFloat(16)),
        (CGSize(width: 169, height: 228), CGFloat(8)),
    ])
    func `The gap between rows scales with the keys`(size: CGSize, gap: CGFloat) {
        #expect(KeypadLayout.rowGap(inKeypadOf: size, count: Self.count) == gap)
    }

    @Test(arguments: [
        (0, CGSize.zero),
        (1, CGSize(width: 338, height: 126)),
        (10, CGSize(width: 338, height: 456)),
    ])
    func `The keypad takes whole rows for its keys`(count: Int, size: CGSize) {
        #expect(KeypadLayout.size(fitting: .unspecified, count: count) == size)
    }
}
