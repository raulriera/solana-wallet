import SwiftUI

/// Marks a label with a red symbol and keeps its text in the window's primary text color.
struct WarningLabelStyle: LabelStyle {
    /// Colors the symbol red and the title with the window's primary text color.
    /// - Parameter configuration: The label's title and symbol.
    /// - Returns: A native label with the warning colors.
    func makeBody(configuration: Configuration) -> some View {
        Label {
            configuration.title
                .foregroundStyle(.red)
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
