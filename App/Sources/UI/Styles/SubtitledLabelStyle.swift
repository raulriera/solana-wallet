import SwiftUI

/// A label style that shows the icon beside the title's views stacked as a title and subtitle, with a list row's
/// separator starting at the title.
struct SubtitledLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 12) {
            configuration.icon
            VStack(alignment: .leading, spacing: 2) {
                configuration.title
            }
            .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
        }
    }
}

extension LabelStyle where Self == SubtitledLabelStyle {
    /// A label with its icon beside a title stacked over a subtitle.
    static var subtitled: Self { Self() }
}
