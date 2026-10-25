import SwiftUI

/// Runs each rename while an account's screen is on screen and explains a failure.
private struct AccountRenameLifecycle: ViewModifier {
    @Environment(AccountStore.self) private var store
    @Bindable var rename: AccountRenameModel

    /// Awaits one rename at a time and presents its failure.
    /// - Parameter content: The account's screen.
    /// - Returns: The screen with managed renames and failure presentation.
    func body(content: Content) -> some View {
        let attempt = rename.attempt
        content
            .task(id: attempt) { await rename.run(attempt, store: store) }
            .errorAlert($rename.error)
    }
}

extension AccountScreen {
    /// Runs the screen's renames while it's on screen.
    /// - Returns: The screen with managed renames and failure presentation.
    func accountRenameLifecycle() -> some View {
        modifier(AccountRenameLifecycle(rename: rename))
    }
}
