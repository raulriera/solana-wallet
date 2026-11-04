import SwiftUI

/// A modifier that runs account renames and presents their errors.
private struct AccountRenameLifecycle: ViewModifier {
    @Environment(AccountStore.self) private var store
    @Bindable var rename: AccountRenameModel

    func body(content: Content) -> some View {
        let attempt = rename.attempt
        content
            .task(id: attempt) { await rename.run(attempt, store: store) }
            .alert(error: $rename.error)
    }
}

extension AccountScreen {
    /// Runs the screen's renames and presents their errors.
    ///
    /// - Returns: The screen with managed renames.
    func accountRenameLifecycle() -> some View {
        modifier(AccountRenameLifecycle(rename: rename))
    }
}
