import SwiftUI

/// A label style with a red symbol and red text.
struct WarningLabelStyle: LabelStyle {
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
    /// A label with a red symbol and red text.
    static var warning: Self { Self() }
}
