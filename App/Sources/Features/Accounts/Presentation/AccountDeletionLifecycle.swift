import SwiftUI

/// Runs each confirmed deletion while the accounts list is on screen and explains a failure.
///
/// The list runs it, not the account's screen, because that screen closes as the person confirms; the account's row
/// then leaves the list in view.
struct AccountDeletionLifecycle: ViewModifier {
    @Environment(AccountStore.self) private var store
    @Bindable var deletion: AccountDeletionModel

    /// Awaits one deletion at a time and presents its failure.
    /// - Parameter content: The accounts list.
    /// - Returns: The list with managed deletions and failure presentation.
    func body(content: Content) -> some View {
        let attempt = deletion.attempt
        content
            .task(id: attempt) { await deletion.run(attempt, store: store) }
            .errorAlert($deletion.error)
    }
}
