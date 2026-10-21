import SwiftUI

/// Places an input screen's committing action at the trailing edge of the top toolbar as a prominent checkmark.
#warning("This doesn't belong in 'Layout'")
private struct ConfirmationAction: ViewModifier {
    let title: LocalizedStringResource
    let isEnabled: Bool
    let isPending: Bool
    let action: () -> Void

    /// Adds the confirm button, which shows a spinner in place of its checkmark while the action's work runs.
    /// - Parameter content: The input screen.
    /// - Returns: The screen with its committing action in the top toolbar.
    func body(content: Content) -> some View {
        content
            .toolbar {
                // Pinned, so the commit never moves into the overflow menu.
                ToolbarItem(placement: .topBarPinnedTrailing) {
                    Button(role: .confirm, action: action) {
                        if isPending {
                            ProgressView()
                        } else {
                            Label {
                                Text(title)
                            } icon: {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    // VoiceOver keeps the action's name while the spinner shows.
                    .accessibilityLabel(Text(title))
                    .disabled(!isEnabled || isPending)
                }
            }
    }
}

extension View {
    /// Adds an input screen's committing action as a prominent checkmark at the trailing edge of the top toolbar.
    /// - Parameters:
    ///   - title: The action's name, which VoiceOver reads; the toolbar shows only the checkmark.
    ///   - isEnabled: Whether the input is ready to commit.
    ///   - isPending: Whether the action's work is running, so a spinner replaces the checkmark and the button
    ///     is disabled.
    ///   - action: Commits the input.
    /// - Returns: The view with its committing action in the top toolbar.
    func confirmationAction(_ title: LocalizedStringResource, isEnabled: Bool, isPending: Bool = false,
                            action: @escaping () -> Void) -> some View {
        modifier(ConfirmationAction(title: title, isEnabled: isEnabled, isPending: isPending, action: action))
    }
}
