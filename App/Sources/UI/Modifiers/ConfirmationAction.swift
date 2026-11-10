import SwiftUI

/// Adds an input screen's committing action as a prominent symbol at the trailing edge of the top toolbar.
private struct ConfirmationAction: ViewModifier {
    let title: LocalizedStringResource
    let isEnabled: Bool
    let isPending: Bool
    let action: () -> Void

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarPinnedTrailing) {
                    Button(role: .confirm, action: action) {
                        if isPending {
                            ProgressView()
                                .tint(.secondary)
                        } else {
                            Label {
                                Text(title)
                            } icon: {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    .accessibilityLabel(Text(title))
                    .disabled(!isEnabled || isPending)
                }
            }
    }
}

extension View {
    /// Adds an input screen's committing action as a prominent symbol at the trailing edge of the top toolbar.
    ///
    /// - Parameters:
    ///   - title: The action's name.
    ///   - isEnabled: Whether the input is ready to commit.
    ///   - isPending: Whether the action's work is running.
    ///   - action: The action that commits the input.
    /// - Returns: The view with its committing action in the top toolbar.
    func confirmationAction(_ title: LocalizedStringResource, isEnabled: Bool,
                            isPending: Bool = false, action: @escaping () -> Void) -> some View {
        modifier(ConfirmationAction(title: title, isEnabled: isEnabled, isPending: isPending,
                                    action: action))
    }
}
