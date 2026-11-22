import SwiftUI

/// A screen that explains why its content is unavailable, with an optional action.
struct UnavailableScreen<Action: View>: View {
    @Environment(\.palette) private var palette
    private let title: LocalizedStringResource
    private let message: LocalizedStringResource
    private let systemImage: String
    private let action: Action?

    /// Creates an unavailable screen.
    ///
    /// - Parameters:
    ///   - title: What is unavailable.
    ///   - message: Why it's unavailable and what the action does.
    ///   - systemImage: The name of the SF Symbol that shows the cause.
    ///   - action: The one action that can fix it, or `nil` for none.
    init(title: LocalizedStringResource, message: LocalizedStringResource, systemImage: String,
         @ViewBuilder action: () -> Action?) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.action = action()
    }

    var body: some View {
        ScrollView {
            ContentUnavailableView {
                Label(title, systemImage: systemImage)
            } description: {
                Text(message)
            } actions: {
                action
            }
            .drawOnAppear()
            .frame(maxWidth: LayoutMetrics.readableWidth)
        }
        .defaultScrollAnchor(.center, for: .alignment)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.background)
    }
}
