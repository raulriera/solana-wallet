import SwiftUI

/// Adds a cancel button at the leading edge of a presented screen's top toolbar.
private struct CancellationAction: ViewModifier {
    @Environment(\.dismiss) private var dismiss
    /// The action to run, or `nil` to dismiss the screen.
    let action: (() -> Void)?

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark", role: .cancel) {
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
        modifier(CancellationAction(action: action))
    }
}
