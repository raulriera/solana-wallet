import SwiftUI

/// Places an input screen's committing action at the trailing edge of the top toolbar as a prominent symbol, a
/// checkmark unless the action names its own.
private struct ConfirmationAction: ViewModifier {
    let title: LocalizedStringResource
    let systemImage: String
    let isEnabled: Bool
    let isPending: Bool
    let action: () -> Void

    /// Adds the confirm button, which shows a spinner in place of its symbol while the action's work runs.
    /// - Parameter content: The input screen.
    /// - Returns: The screen with its committing action in the top toolbar.
    func body(content: Content) -> some View {
        content
            .toolbar {
                // Pinned, so the commit never moves into the overflow menu.
                ToolbarItem(placement: .topBarPinnedTrailing) {
                    Button(role: .confirm, action: action) {
                        if isPending {
                            // The button is gray while it works, so the spinner is gray too.
                            ProgressView()
                                .tint(.secondary)
                        } else {
                            Label {
                                Text(title)
                            } icon: {
                                Image(systemName: systemImage)
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
    /// Adds an input screen's committing action as a prominent symbol at the trailing edge of the top toolbar.
    /// - Parameters:
    ///   - title: The action's name, which VoiceOver reads; the toolbar shows only the symbol.
    ///   - systemImage: The SF Symbol that shows the action, a checkmark unless the action says what it does, such as
    ///     moving SOL into the private balance.
    ///   - isEnabled: Whether the input is ready to commit.
    ///   - isPending: Whether the action's work is running, so a spinner replaces the symbol and the button
    ///     is disabled.
    ///   - action: Commits the input.
    /// - Returns: The view with its committing action in the top toolbar.
    func confirmationAction(_ title: LocalizedStringResource, systemImage: String = "checkmark", isEnabled: Bool,
                            isPending: Bool = false, action: @escaping () -> Void) -> some View {
        modifier(ConfirmationAction(title: title, systemImage: systemImage, isEnabled: isEnabled, isPending: isPending,
                                    action: action))
    }
}
