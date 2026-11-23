import SwiftUI

/// A labeled content style that shows the label's first view over the rest, which show as subheadlines in the
/// secondary foreground style, with the content after them.
struct SubtitledLabeledContentStyle: LabeledContentStyle {
    private let spacing: CGFloat?

    /// Creates a subtitled style.
    ///
    /// - Parameter spacing: The distance between the label's views, or `nil` for the default.
    fileprivate init(spacing: CGFloat?) {
        self.spacing = spacing
    }

    func makeBody(configuration: Configuration) -> some View {
        HStack {
            Group(subviews: configuration.label) { subviews in
                VStack(alignment: .leading, spacing: spacing) {
                    subviews.first
                    subviews.dropFirst()
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            configuration.content
        }
    }
}

extension LabeledContentStyle where Self == SubtitledLabeledContentStyle {
    /// Returns a style that shows the label's first view over the rest as secondary subheadlines.
    ///
    /// - Parameter spacing: The distance between the label's views, or `nil` for the default.
    /// - Returns: The subtitled style.
    static func subtitled(spacing: CGFloat?) -> Self {
        Self(spacing: spacing)
    }
}
