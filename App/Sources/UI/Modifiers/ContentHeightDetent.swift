import SwiftUI

/// Sizes a sheet to its scrolling content, top bar included, for a sheet that holds little, such as a review.
///
/// The sheet follows its content as it changes, such as when a result replaces a review.
private struct ContentHeightDetent: ViewModifier {
    /// The sheet's only detent: the medium detent until the content is measured, then the content's height.
    @State private var detent = PresentationDetent.medium

    /// Measures the content and selects its height as the sheet's only detent.
    /// - Parameter content: The sheet's scrolling content.
    /// - Returns: The content, sized to its height once measured.
    func body(content: Content) -> some View {
        content
            // The sheet already reserves the home indicator, so the bottom inset isn't added again.
            //
            // Known issue, to revisit: when one screen replaces another in the same sheet, such as a result replacing
            // a review, one layout pass reports no top inset under the bar, so the height reads too small. A sheet
            // that is already presented takes that height and then ignores the correct one that follows, so its
            // content is cut off. Why the sheet ignores the later height is unknown; a probe outside the app
            // couldn't reproduce it. Until the cause is understood, measurements without the bar's inset are skipped.
            .onScrollGeometryChange(for: CGFloat?.self) { geometry in
                guard geometry.contentInsets.top > 0 else { return nil }
                return geometry.contentSize.height + geometry.contentInsets.top
            } action: { _, height in
                if let height { detent = .height(height) }
            }
            // Selecting the new detent, not only offering it, resizes a sheet that is already presented.
            .presentationDetents([detent], selection: $detent)
    }
}

extension View {
    /// Sizes the sheet that presents this scrolling content to the content's height, top bar included.
    /// - Returns: The content, which sets its sheet's detent.
    func contentHeightDetent() -> some View {
        modifier(ContentHeightDetent())
    }
}
