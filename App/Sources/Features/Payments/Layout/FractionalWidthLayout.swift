import SwiftUI

/// Offers its content a share of the width it's given, up to a maximum, and centers it in the full width.
struct FractionalWidthLayout: Layout {
    /// The share of the offered width the content gets.
    let fraction: CGFloat
    /// The widest the content gets.
    let maximumWidth: CGFloat

    /// Takes the offered width and the height the content needs at its share of that width.
    /// - Parameters:
    ///   - proposal: The space offered to the layout.
    ///   - subviews: The content, as one subview.
    ///   - cache: Unused.
    /// - Returns: The offered width and the content's height.
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let content = subviews.first else { return .zero }
        let width = proposal.width ?? content.sizeThatFits(.unspecified).width
        let size = content.sizeThatFits(contentProposal(width: width, height: proposal.height))
        return CGSize(width: width, height: size.height)
    }

    /// Centers the content at its share of the layout's width.
    /// - Parameters:
    ///   - bounds: The layout's frame.
    ///   - proposal: The space offered to the layout.
    ///   - subviews: The content, as one subview.
    ///   - cache: Unused.
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: CGPoint(x: bounds.midX, y: bounds.midY), anchor: .center,
                              proposal: contentProposal(width: bounds.width, height: bounds.height))
    }

    /// The size offered to the content for a given width and height.
    /// - Parameters:
    ///   - width: The layout's width.
    ///   - height: The layout's height, if known.
    /// - Returns: The content's share of the width with the same height.
    private func contentProposal(width: CGFloat, height: CGFloat?) -> ProposedViewSize {
        ProposedViewSize(width: min(width * fraction, maximumWidth), height: height)
    }
}

extension View {
    /// Gives this view a share of the width it's offered, up to a maximum, centered in the full width.
    /// - Parameters:
    ///   - fraction: The share of the offered width this view gets.
    ///   - maximumWidth: The widest this view gets.
    /// - Returns: The view laid out at its share of the width.
    func fractionalWidth(_ fraction: CGFloat, maximum maximumWidth: CGFloat) -> some View {
        FractionalWidthLayout(fraction: fraction, maximumWidth: maximumWidth) { self }
    }
}
