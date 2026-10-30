import SwiftUI
import Testing
@testable import widgets

struct ArrangementPlanTests {
    private static let spacing: CGFloat = 8

    private static func keypadScreen(_ region: ArrangementPlan.Region, _ proposal: ProposedViewSize) -> CGSize {
        switch region {
        case .primary:
            return CGSize(width: proposal.width ?? 222, height: proposal.height ?? 154)
        case .secondary:
            let scale = min(1, (proposal.width ?? 386) / 386, (proposal.height ?? 488) / 488)
            return CGSize(width: 386 * scale, height: 488 * scale)
        case .accessory:
            return CGSize(width: proposal.width ?? 82, height: 50)
        }
    }

    private static func keypadPlan(_ size: CGSize, fold: CGRect? = nil) -> ArrangementPlan {
        ArrangementPlan(size: size, fold: fold, accessorySpacing: spacing, measure: keypadScreen)
    }

    @Test func `Regions that fit stack together in the middle with Send under the keys`() {
        let plan = Self.keypadPlan(CGSize(width: 800, height: 1000))

        #expect(plan.axis == .vertical)
        #expect(plan.primary == CGRect(x: 0, y: 150, width: 800, height: 154))
        #expect(plan.secondary == CGRect(x: 207, y: 304, width: 386, height: 488))
        #expect(plan.accessory == CGRect(x: 207, y: 800, width: 386, height: 50))
    }

    @Test func `Wide space puts the keys beside the amount with Send under it at the keys' width`() {
        let plan = Self.keypadPlan(CGSize(width: 900, height: 600))

        #expect(plan.axis == .horizontal)
        #expect(plan.secondary == CGRect(x: 482, y: 56, width: 386, height: 488))
        #expect(plan.accessory == CGRect(x: 32, y: 550, width: 386, height: 50))
        #expect(plan.primary == CGRect(x: 0, y: 0, width: 450, height: 542))
    }

    @Test func `Wide space places the regions side by side even when they would fit stacked`() {
        let plan = Self.keypadPlan(CGSize(width: 1400, height: 1000))

        #expect(plan.axis == .horizontal)
        #expect(plan.secondary == CGRect(x: 857, y: 256, width: 386, height: 488))
    }

    @Test func `Short tall space stays stacked and the keys give up height`() throws {
        let plan = Self.keypadPlan(CGSize(width: 300, height: 500))
        let accessory = try #require(plan.accessory)

        #expect(plan.axis == .vertical)
        #expect(plan.primary == CGRect(x: 0, y: 0, width: 300, height: 154))
        #expect(plan.secondary.minY == 154)
        #expect(plan.secondary.height == 288)
        #expect(accessory.minY == plan.secondary.maxY + Self.spacing)
        #expect(accessory.maxY == 500)
    }

    @Test func `A horizontal fold stacks the regions on either side of it`() {
        let plan = Self.keypadPlan(CGSize(width: 900, height: 600), fold: CGRect(x: 0, y: 290, width: 900, height: 20))

        #expect(plan.axis == .vertical)
        #expect(plan.primary == CGRect(x: 0, y: 0, width: 900, height: 290))
        #expect(plan.secondary.minY == 310)
        #expect(plan.accessory.map(\.maxY) == 600)
    }

    @Test func `A vertical fold places the regions side by side on either side of it`() {
        let plan = Self.keypadPlan(CGSize(width: 900, height: 600), fold: CGRect(x: 440, y: 0, width: 20, height: 600))

        #expect(plan.axis == .horizontal)
        #expect(plan.primary.maxX == 440)
        #expect(plan.secondary.minX >= 460)
        #expect(plan.accessory.map(\.maxX).map { $0 <= 440 } == true)
    }

    @Test func `A fold near an edge keeps the regions on its larger side`() {
        let plan = Self.keypadPlan(CGSize(width: 450, height: 600), fold: CGRect(x: 440, y: 0, width: 20, height: 600))

        #expect(plan.axis == .vertical)
        #expect(plan.primary.width == 440)
    }

    @Test(arguments: [
        (CGSize(width: 800, height: 400), CGRect(x: 0, y: 0, width: 400, height: 400),
         CGRect(x: 400, y: 0, width: 400, height: 400)),
        (CGSize(width: 400, height: 800), CGRect(x: 0, y: 100, width: 400, height: 300),
         CGRect(x: 0, y: 400, width: 400, height: 300)),
    ])
    func `Scrolling regions without an accessory sit side by side or stack together`(size: CGSize, primary: CGRect,
                                                                                      secondary: CGRect) {
        let plan = ArrangementPlan(size: size, fold: nil, accessorySpacing: nil) { _, proposal in
            CGSize(width: proposal.width ?? 300, height: proposal.height ?? 300)
        }

        #expect(plan.primary == primary)
        #expect(plan.secondary == secondary)
        #expect(plan.accessory == nil)
    }
}
