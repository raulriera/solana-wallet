import SwiftUI

/// Marks a label with a red symbol and red text.
struct WarningLabelStyle: LabelStyle {
    /// Colors the symbol and the title red.
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
    /// A label with a red symbol and red text, for errors and destructive actions.
    static var warning: Self { Self() }
}
