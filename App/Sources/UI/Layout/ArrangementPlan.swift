import SwiftUI

/// Where an adaptive arrangement puts its regions, from the space it has and the space their content uses.
///
/// Frames are relative to the arrangement's origin.
nonisolated struct ArrangementPlan: Equatable {
    /// A view the plan measures.
    nonisolated enum Region {
        case primary
        case secondary
        /// The secondary region's second view, which follows the primary region when the regions sit side by side.
        case accessory
    }

    /// The direction the regions follow: horizontal for side by side, vertical for stacked.
    let axis: Axis
    /// The primary region's frame.
    let primary: CGRect
    /// The secondary region's frame.
    let secondary: CGRect
    /// The accessory's frame, or `nil` when the secondary region has none.
    let accessory: CGRect?

    /// Fills the top area with the primary region and centers the secondary region, with its accessory below it, in
    /// the bottom area.
    /// - Parameters:
    ///   - top: The primary region's area.
    ///   - bottom: The area for the secondary region and its accessory.
    ///   - accessorySpacing: The space above the accessory, or `nil` when there's none.
    ///   - measure: The size a region's view takes for a proposal.
    /// - Returns: The stacked plan.
    private static func stacked(primaryIn top: CGRect, secondaryIn bottom: CGRect, accessorySpacing: CGFloat?,
                                measure: (Region, ProposedViewSize) -> CGSize) -> Self {
        let accessoryHeight = accessoryHeight(width: bottom.width, spacing: accessorySpacing, measure: measure)
        let size = measure(.secondary, ProposedViewSize(width: bottom.width, height: bottom.height - accessoryHeight))
        let secondary = CGRect(x: bottom.midX - size.width / 2,
                               y: bottom.minY + max(bottom.height - size.height - accessoryHeight, 0) / 2,
                               width: size.width, height: size.height)
        let accessory = accessorySpacing.map { spacing in
            CGRect(x: secondary.minX, y: secondary.maxY + spacing, width: secondary.width,
                   height: accessoryHeight - spacing)
        }
        return Self(axis: .vertical, primary: top, secondary: secondary, accessory: accessory)
    }

    /// Centers the secondary region in the trailing area and fills the leading area with the primary region, with the
    /// accessory at its bottom.
    /// - Parameters:
    ///   - leading: The area for the primary region and the accessory.
    ///   - trailing: The secondary region's area.
    ///   - accessorySpacing: The space above the accessory, or `nil` when there's none.
    ///   - measure: The size a region's view takes for a proposal.
    /// - Returns: The side-by-side plan.
    private static func sideBySide(primaryIn leading: CGRect, secondaryIn trailing: CGRect,
                                   accessorySpacing: CGFloat?,
                                   measure: (Region, ProposedViewSize) -> CGSize) -> Self {
        let size = measure(.secondary, ProposedViewSize(trailing.size))
        let secondary = CGRect(x: trailing.midX - size.width / 2, y: trailing.midY - size.height / 2,
                               width: size.width, height: size.height)
        guard let accessorySpacing else {
            return Self(axis: .horizontal, primary: leading, secondary: secondary, accessory: nil)
        }
        let width = min(secondary.width, leading.width)
        let height = measure(.accessory, ProposedViewSize(width: width, height: nil)).height
        let accessory = CGRect(x: leading.midX - width / 2, y: leading.maxY - height, width: width, height: height)
        let primary = CGRect(x: leading.minX, y: leading.minY, width: leading.width,
                             height: max(accessory.minY - accessorySpacing - leading.minY, 0))
        return Self(axis: .horizontal, primary: primary, secondary: secondary, accessory: accessory)
    }

    /// The height the accessory and the space above it take.
    /// - Parameters:
    ///   - width: The width offered to the accessory.
    ///   - spacing: The space above the accessory, or `nil` when there's none.
    ///   - measure: The size a region's view takes for a proposal.
    /// - Returns: The accessory's height plus its spacing, or zero without an accessory.
    private static func accessoryHeight(width: CGFloat, spacing: CGFloat?,
                                        measure: (Region, ProposedViewSize) -> CGSize) -> CGFloat {
        guard let spacing else { return 0 }
        return measure(.accessory, ProposedViewSize(width: width, height: nil)).height + spacing
    }
}

nonisolated extension ArrangementPlan {
    /// Splits at an active fold through the middle of the space. Otherwise places the regions side by side in space
    /// wider than tall, and stacks them in other space: close together when they fit at the height their content uses,
    /// or with the secondary region giving up height.
    /// - Parameters:
    ///   - size: The space the arrangement has.
    ///   - fold: The active fold that crosses the space, if any.
    ///   - accessorySpacing: The space between the accessory and the region above it, or `nil` when there's no
    ///     accessory.
    ///   - measure: The size a region's view takes for a proposal.
    init(size: CGSize, fold: CGRect?, accessorySpacing: CGFloat?, measure: (Region, ProposedViewSize) -> CGSize) {
        var space = CGRect(origin: .zero, size: size)
        if let fold, fold.intersects(space) {
            // A fold through the middle divides the space; one nearer an edge only trims that edge.
            if fold.width > fold.height {
                let above = CGRect(x: space.minX, y: space.minY, width: space.width,
                                   height: max(fold.minY - space.minY, 0))
                let below = CGRect(x: space.minX, y: fold.maxY, width: space.width,
                                   height: max(space.maxY - fold.maxY, 0))
                if (fold.minY...fold.maxY).contains(space.midY) {
                    self = Self.stacked(primaryIn: above, secondaryIn: below, accessorySpacing: accessorySpacing,
                                        measure: measure)
                    return
                }
                space = above.height > below.height ? above : below
            } else {
                let leading = CGRect(x: space.minX, y: space.minY, width: max(fold.minX - space.minX, 0),
                                     height: space.height)
                let trailing = CGRect(x: fold.maxX, y: space.minY, width: max(space.maxX - fold.maxX, 0),
                                      height: space.height)
                if (fold.minX...fold.maxX).contains(space.midX) {
                    self = Self.sideBySide(primaryIn: leading, secondaryIn: trailing,
                                           accessorySpacing: accessorySpacing, measure: measure)
                    return
                }
                space = leading.width > trailing.width ? leading : trailing
            }
        }

        if space.width > space.height {
            let (leading, trailing) = space.divided(atDistance: space.width / 2, from: .minXEdge)
            self = Self.sideBySide(primaryIn: leading, secondaryIn: trailing, accessorySpacing: accessorySpacing,
                                   measure: measure)
            return
        }
        // Regions that fit stay together in the middle; otherwise the primary region keeps the height its content uses
        // and the secondary region gives up height.
        let accessoryHeight = Self.accessoryHeight(width: space.width, spacing: accessorySpacing, measure: measure)
        let primaryHeight = measure(.primary, ProposedViewSize(width: space.width, height: nil)).height
        let secondaryHeight = measure(.secondary, ProposedViewSize(width: space.width, height: nil)).height
        let contentHeight = primaryHeight + secondaryHeight + accessoryHeight
        let top = space.minY + max(space.height - contentHeight, 0) / 2
        let primary = CGRect(x: space.minX, y: top, width: space.width,
                             height: min(primaryHeight, space.height - accessoryHeight))
        let rest = CGRect(x: space.minX, y: primary.maxY, width: space.width,
                          height: min(secondaryHeight + accessoryHeight, space.maxY - primary.maxY))
        self = Self.stacked(primaryIn: primary, secondaryIn: rest, accessorySpacing: accessorySpacing,
                            measure: measure)
    }
}
