import SwiftUI

/// A layout that places a primary region, a secondary region, and its optional accessory where an
/// ``ArrangementPlan`` puts them.
struct AdaptiveArrangementLayout: Layout {
    /// The active fold's frame in the arrangement's coordinates.
    let fold: CGRect?

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

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

    /// Places a view at a frame in the arrangement's coordinates.
    ///
    /// - Parameters:
    ///   - subview: The view to place.
    ///   - frame: The view's frame, relative to the arrangement's origin.
    ///   - bounds: The arrangement's frame.
    private func place(_ subview: LayoutSubview, in frame: CGRect, within bounds: CGRect) {
        subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), anchor: .topLeading,
                      proposal: ProposedViewSize(frame.size))
    }
}
