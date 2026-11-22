import SwiftUI

/// A label style that shows the icon beside the title's first view stacked over the rest as secondary subheadlines,
/// with a list row's separator starting at the title.
struct SubtitledLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 12) {
            configuration.icon
            Group(subviews: configuration.title) { subviews in
                VStack(alignment: .leading, spacing: 2) {
                    subviews.first
                    subviews.dropFirst()
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
        }
    }
}

extension LabelStyle where Self == SubtitledLabelStyle {
    /// A label with its icon beside a title stacked over a subtitle.
    static var subtitled: Self { Self() }
}
