import SwiftUI

/// Adds a cancel or close button at the leading edge of a presented screen's top toolbar.
private struct CancellationAction: ViewModifier {
    @Environment(\.dismiss) private var dismiss
    let title: LocalizedStringResource
    let role: ButtonRole
    /// The action to run, or `nil` to dismiss the screen.
    let action: (() -> Void)?

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(title, systemImage: "xmark", role: role) {
                        if let action { action() } else { dismiss() }
                    }
                    .tint(.primary)
                }
            }
    }
}

extension View {
    /// Adds a cancel button at the leading edge of a presented screen's top toolbar.
    ///
    /// - Parameter action: What canceling does, or `nil` to dismiss the screen.
    /// - Returns: The view with a cancel action.
    func cancellationAction(_ action: (() -> Void)? = nil) -> some View {
        modifier(CancellationAction(title: "Cancel", role: .cancel, action: action))
    }

    /// Adds a close button for a finished task at the leading edge of a presented screen's top toolbar.
    ///
    /// - Parameter action: What closing does, or `nil` to dismiss the screen.
    /// - Returns: The view with a close action.
    func closeAction(_ action: (() -> Void)? = nil) -> some View {
        modifier(CancellationAction(title: "Close", role: .close, action: action))
    }
}
