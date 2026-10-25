import SwiftUI

extension AccountsScreen {
    /// Runs the list's account additions and the deletions that the person confirmed, while the list is on screen.
    /// - Returns: The screen with managed additions and deletions, and their failure presentation.
    func accountsLifecycle() -> some View {
        modifier(AccountAdditionLifecycle(addition: addition).concat(AccountDeletionLifecycle(deletion: deletion)))
    }
}
