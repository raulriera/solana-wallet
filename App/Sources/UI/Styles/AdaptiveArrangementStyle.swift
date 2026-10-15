import SwiftUI

/// Places an arrangement's regions stacked or side by side from the space it has, and around an active fold.
///
/// A fold that divides the space into two usable parts splits the regions at it: stacked across a horizontal fold,
/// so on iPhone Duo in a table pose the secondary region sits on the flat half, or side by side along a vertical
/// one. A fold too close to an edge to split around keeps the regions on its larger side. Each region reads the chosen
/// direction from ``EnvironmentValues/arrangementAxis``.
///
/// The system's `.split` style shows only the primary region in short space, such as iPhone in landscape, so this
/// style picks the direction itself.
struct AdaptiveArrangementStyle: ArrangementViewStyle {
    /// The primary region's share of the height when the regions stack and no fold sets the split, or `nil` to give
    /// the secondary region the height its content uses and the primary region the rest.
    var stackedPrimaryShare: CGFloat? = 0.5
    /// How many times wider than tall the space must be to place the regions side by side.
    var sideBySideAspectRatio: CGFloat = 1
    /// The height at which stacked regions have all the room they use; taller space always stacks them. Without
    /// one, any space wide enough for ``sideBySideAspectRatio`` places them side by side.
    var fullStackedHeight: CGFloat?
    /// The shortest height that still fits both regions stacked; shorter space that's wider than tall places them
    /// side by side at any aspect ratio.
    var minimumStackedHeight: CGFloat?

    /// Lays out the same two regions in either direction without replacing their view identities.
    /// - Parameter configuration: The primary and secondary regions supplied by the arrangement.
    /// - Returns: The regions side by side or stacked, around a fold when one is active.
    func makeBody(configuration: Configuration) -> some View {
        GeometryReader { geometry in
            let split = ArrangementSplit(geometry: geometry, stackedPrimaryShare: stackedPrimaryShare,
                                         sideBySideAspectRatio: sideBySideAspectRatio,
                                         fullStackedHeight: fullStackedHeight, minimumStackedHeight: minimumStackedHeight)
            let layout = split.axis == .horizontal
                ? AnyLayout(HStackLayout(spacing: split.gap))
                : AnyLayout(VStackLayout(spacing: split.gap))

            layout {
                configuration.primary
                    .frame(width: split.axis == .horizontal ? split.primaryLength : nil,
                           height: split.axis == .vertical ? split.primaryLength : nil)
                configuration.secondary
                    // Without a set length, the secondary region takes the height its content uses first.
                    .layoutPriority(split.primaryLength == nil ? 1 : 0)
            }
            .environment(\.arrangementAxis, split.axis)
            .frame(width: split.bounds.width, height: split.bounds.height, alignment: split.alignment)
            .offset(x: split.bounds.minX, y: split.bounds.minY)
        }
    }
}

/// Where an adaptive arrangement places and divides its regions.
private struct ArrangementSplit {
    /// The smallest share of the space each side of a fold needs before the regions split at it.
    private static let minimumFoldShare: CGFloat = 0.3

    /// The part of the space the regions use: all of it, or the larger side of a fold too close to an edge.
    let bounds: CGRect
    /// The direction the regions follow: horizontal for side by side, vertical for stacked.
    let axis: Axis
    /// The primary region's width when side by side, or its height when stacked; `nil` leaves it the height the
    /// secondary region doesn't use.
    let primaryLength: CGFloat?
    /// The space between the regions, which covers a fold they split at.
    let gap: CGFloat
    /// Where regions that don't fill the space sit: at the top leading corner when split at a fold, so the gap stays
    /// on the fold; otherwise centered in the height, so stacked regions stay together.
    let alignment: Alignment

    /// Splits at a usable fold; otherwise picks the direction from the space the regions have.
    /// - Parameters:
    ///   - geometry: The arrangement's space and reserved regions.
    ///   - stackedPrimaryShare: The primary region's share of the height when stacked without a fold, or `nil` to
    ///     leave it the height the secondary region doesn't use.
    ///   - sideBySideAspectRatio: How many times wider than tall the space must be to place the regions side by side.
    ///   - fullStackedHeight: The height at which stacked regions have all the room they use, if the arrangement has
    ///     one.
    ///   - minimumStackedHeight: The shortest height that fits the regions stacked, if the arrangement has one.
    init(geometry: GeometryProxy, stackedPrimaryShare: CGFloat?, sideBySideAspectRatio: CGFloat,
         fullStackedHeight: CGFloat?, minimumStackedHeight: CGFloat?) {
        var bounds = CGRect(origin: .zero, size: geometry.size)
        let folds = geometry.reservedRegions(kind: .division).filter(\.isActive).map(\.frame)
            .filter { $0.intersects(bounds) }

        if let fold = folds.first(where: { $0.width > $0.height }) {
            let above = fold.minY - bounds.minY
            let below = bounds.maxY - fold.maxY
            if min(above, below) >= bounds.height * Self.minimumFoldShare {
                self.bounds = bounds
                axis = .vertical
                primaryLength = above
                gap = fold.height
                alignment = .topLeading
                return
            }
            bounds = above > below
                ? CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: above)
                : CGRect(x: bounds.minX, y: fold.maxY, width: bounds.width, height: below)
        } else if let fold = folds.first(where: { $0.height > $0.width }) {
            let leading = fold.minX - bounds.minX
            let trailing = bounds.maxX - fold.maxX
            if min(leading, trailing) >= bounds.width * Self.minimumFoldShare {
                self.bounds = bounds
                axis = .horizontal
                primaryLength = leading
                gap = fold.width
                alignment = .topLeading
                return
            }
            bounds = leading > trailing
                ? CGRect(x: bounds.minX, y: bounds.minY, width: leading, height: bounds.height)
                : CGRect(x: fold.maxX, y: bounds.minY, width: trailing, height: bounds.height)
        }

        let isWide = bounds.width > bounds.height
        let isWideEnough = bounds.width >= bounds.height * sideBySideAspectRatio
            && fullStackedHeight.map { bounds.height < $0 } ?? true
        let isTooShort = minimumStackedHeight.map { bounds.height < $0 } ?? false
        self.bounds = bounds
        gap = 0
        alignment = .leading
        if isWide && (isWideEnough || isTooShort) {
            axis = .horizontal
            primaryLength = bounds.width / 2
        } else {
            axis = .vertical
            primaryLength = stackedPrimaryShare.map { bounds.height * $0 }
        }
    }
}

extension EnvironmentValues {
    /// The direction an adaptive arrangement gave its regions: horizontal for side by side, vertical for stacked.
    @Entry var arrangementAxis: Axis = .vertical
}

extension ArrangementViewStyle where Self == AdaptiveArrangementStyle {
    /// Side by side whenever the space is wider than tall, stacked otherwise, around an active fold, with equal
    /// shares.
    static var adaptive: Self { Self() }

    /// Stacked unless the space is wide enough and too short for the regions' full stacked height, or wider than
    /// tall and too short to stack at all, around an active fold. Stacked, the secondary region takes the height its
    /// content uses and the primary region the rest.
    /// - Parameters:
    ///   - sideBySideAspectRatio: How many times wider than tall the space must be to place the regions side by side.
    ///   - fullStackedHeight: The height at which stacked regions have all the room they use.
    ///   - minimumStackedHeight: The shortest height that fits both regions stacked.
    /// - Returns: The adaptive arrangement style.
    static func adaptive(sideBySideAspectRatio: CGFloat, fullStackedHeight: CGFloat,
                         minimumStackedHeight: CGFloat) -> Self {
        Self(stackedPrimaryShare: nil, sideBySideAspectRatio: sideBySideAspectRatio,
             fullStackedHeight: fullStackedHeight, minimumStackedHeight: minimumStackedHeight)
    }
}
