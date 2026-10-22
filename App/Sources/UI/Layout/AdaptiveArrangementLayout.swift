import SwiftUI

/// Places an adaptive arrangement's views where an ``ArrangementPlan`` puts them: the primary region, then the
/// secondary region, then the secondary region's accessory, if it has one.
struct AdaptiveArrangementLayout: Layout {
    /// The active fold that crosses the arrangement, in the arrangement's own coordinates.
    let fold: CGRect?

    /// Takes all the space it's offered, like the regions it divides.
    /// - Parameters:
    ///   - proposal: The space offered to the arrangement.
    ///   - subviews: The primary region, the secondary region, and its accessory.
    ///   - cache: Unused.
    /// - Returns: The offered size.
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    /// Measures the views and places each in the frame the plan gives it.
    /// - Parameters:
    ///   - bounds: The arrangement's frame.
    ///   - proposal: The space offered to the arrangement.
    ///   - subviews: The primary region, the secondary region, and its accessory.
    ///   - cache: Unused.
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count > 1 else { return }
        let primary = subviews[0]
        let secondary = subviews[1]
        let accessory = subviews.dropFirst(2).first
        let spacing = accessory.map { secondary.spacing.distance(to: $0.spacing, along: .vertical) }
        let plan = ArrangementPlan(size: bounds.size, fold: fold, accessorySpacing: spacing) {
            region, proposal in
            switch region {
            case .primary: primary.sizeThatFits(proposal)
            case .secondary: secondary.sizeThatFits(proposal)
            case .accessory: accessory?.sizeThatFits(proposal) ?? .zero
            }
        }
        place(primary, in: plan.primary, within: bounds)
        place(secondary, in: plan.secondary, within: bounds)
        if let accessory, let frame = plan.accessory {
            place(accessory, in: frame, within: bounds)
        }
    }

    /// Places a view at a frame given in the arrangement's own coordinates.
    /// - Parameters:
    ///   - subview: The view to place.
    ///   - frame: Its frame, relative to the arrangement's origin.
    ///   - bounds: The arrangement's frame.
    private func place(_ subview: LayoutSubview, in frame: CGRect, within bounds: CGRect) {
        subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), anchor: .topLeading,
                      proposal: ProposedViewSize(frame.size))
    }
}
