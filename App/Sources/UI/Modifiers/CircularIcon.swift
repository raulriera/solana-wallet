import SwiftUI

/// Shows a decorative icon in a 40 pt circle that grows with the headline text size.
private struct CircularIcon<Background: ShapeStyle>: ViewModifier {
    @ScaledMetric(relativeTo: .headline) private var diameter = 40
    let background: Background

    func body(content: Content) -> some View {
        content
            .frame(width: diameter, height: diameter)
            .background(background)
            .clipShape(.circle)
            .accessibilityHidden(true)
    }
}

extension View {
    /// Shows a decorative icon in a 40 pt circle that grows with the headline text size.
    ///
    /// - Parameter background: The circle's fill behind the icon.
    /// - Returns: The icon in the circle, hidden from assistive technologies.
    func circularIcon(_ background: some ShapeStyle) -> some View {
        modifier(CircularIcon(background: background))
    }

    /// Shows letters, such as a name's initials, in white on a gray circle, as Contacts shows a person without a photo.
    ///
    /// - Returns: The letters in the circle, hidden from assistive technologies.
    func monogramIcon() -> some View {
        font(.headline)
            .minimumScaleFactor(0.5)
            .foregroundStyle(.white)
            .circularIcon(.gray.gradient)
    }
}
