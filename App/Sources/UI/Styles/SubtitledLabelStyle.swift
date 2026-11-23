import SwiftUI

/// A label style that shows the icon beside the title's first view stacked over the rest as secondary subheadlines,
/// each on one line, with a list row's separator starting at the title.
struct SubtitledLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 12) {
            configuration.icon
            LabeledContent {
            } label: {
                configuration.title
            }
            .labeledContentStyle(.subtitled(spacing: 2))
            .lineLimit(1)
            .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
        }
    }
}

extension LabelStyle where Self == SubtitledLabelStyle {
    /// A label with its icon beside a title stacked over subtitles.
    static var subtitled: Self { Self() }
}
