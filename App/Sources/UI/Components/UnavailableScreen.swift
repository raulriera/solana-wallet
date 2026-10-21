import SwiftUI

/// Explains why a screen's content is unavailable and offers the one action that can fix it, if any.
struct UnavailableScreen<Action: View>: View {
    @Environment(\.palette) private var palette
    private let title: LocalizedStringResource
    private let message: LocalizedStringResource
    private let systemImage: String
    private let action: Action?

    /// Creates an explanation with an optional action.
    /// - Parameters:
    ///   - title: What is unavailable.
    ///   - message: Why it's unavailable and what the action does.
    ///   - systemImage: The name of the SF Symbol that pictures the cause.
    ///   - action: The one action that can fix it, usually a button, or `nil` when nothing in the app can.
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
            .foregroundStyle(palette.primaryText, palette.secondaryText)
            .frame(maxWidth: LayoutMetrics.readableWidth)
        }
        .defaultScrollAnchor(.center, for: .alignment)
        // A screen pushed beside a sidebar leaves side margins that the background must still cover.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.background)
    }
}
