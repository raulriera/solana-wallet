import SwiftUI

/// Places a presented screen's cancel action at the leading edge of the top toolbar as a close symbol.
private struct CancellationAction: ViewModifier {
    @Environment(\.dismiss) private var dismiss

    /// Adds the close button, which dismisses the presentation.
    /// - Parameter content: The presented screen.
    /// - Returns: The screen with its cancel action in the top toolbar.
    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // Top-bar items show symbols only; the title stays for VoiceOver. Toolbar buttons keep the
                    // system's monochrome look; the theme's tint is for content.
                    Button("Cancel", systemImage: "xmark", role: .cancel) { dismiss() }
                        .tint(.primary)
                }
            }
    }
}

extension View {
    /// Adds a presented screen's cancel action as a close symbol at the leading edge of the top toolbar.
    /// - Returns: The view with a cancel action that dismisses its presentation.
    func cancellationAction() -> some View {
        modifier(CancellationAction())
    }
}
