import SwiftUI

/// Marks a label with a red symbol and keeps its text in the window's primary text color.
///
/// System red text reads below 4.5:1 on light rows, so only the symbol, which needs 3:1, carries the red.
struct WarningLabelStyle: LabelStyle {
    @Environment(\.palette) private var palette

    /// Colors the symbol red and the title with the window's primary text color.
    /// - Parameter configuration: The label's title and symbol.
    /// - Returns: A native label with the warning colors.
    func makeBody(configuration: Configuration) -> some View {
        Label {
            configuration.title
                .foregroundStyle(palette.primaryText)
        } icon: {
            configuration.icon
                .foregroundStyle(.red)
        }
    }
}

extension LabelStyle where Self == WarningLabelStyle {
    /// A label with a red symbol and text in the window's primary text color, for errors and destructive actions.
    static var warning: Self { Self() }
}
