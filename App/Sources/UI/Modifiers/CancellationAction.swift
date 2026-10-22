import SwiftUI

/// Places a presented screen's cancel or close action at the leading edge of the top toolbar as a close symbol.
private struct CancellationAction: ViewModifier {
    @Environment(\.dismiss) private var dismiss
    /// The action's name, which VoiceOver reads.
    let title: LocalizedStringResource
    /// Whether the action cancels the task or closes a finished one.
    let role: ButtonRole
    /// What the action does instead of dismissing the screen's own presentation, such as closing the sheet that a
    /// pushed screen is in.
    let action: (() -> Void)?

    /// Adds the close button, which runs the action or dismisses the presentation.
    /// - Parameter content: The presented screen.
    /// - Returns: The screen with its cancel or close action in the top toolbar.
    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // Top-bar items show symbols only; the title stays for VoiceOver. Toolbar buttons keep the
                    // system's monochrome look; the theme's tint is for content.
                    Button(title, systemImage: "xmark", role: role) {
                        if let action { action() } else { dismiss() }
                    }
                    .tint(.primary)
                }
            }
    }
}

extension View {
    /// Adds a presented screen's cancel action as a close symbol at the leading edge of the top toolbar.
    /// - Parameter action: What canceling does, such as closing the sheet that a pushed screen is in, or `nil` to
    ///   dismiss the screen's own presentation.
    /// - Returns: The view with a cancel action.
    func cancellationAction(_ action: (() -> Void)? = nil) -> some View {
        modifier(CancellationAction(title: "Cancel", role: .cancel, action: action))
    }

    /// Adds a presented screen's close action, for a task that already finished, as a close symbol at the leading
    /// edge of the top toolbar.
    /// - Parameter action: What closing does, such as closing the sheet that a pushed screen is in, or `nil` to
    ///   dismiss the screen's own presentation.
    /// - Returns: The view with a close action.
    func closeAction(_ action: (() -> Void)? = nil) -> some View {
        modifier(CancellationAction(title: "Close", role: .close, action: action))
    }
}
