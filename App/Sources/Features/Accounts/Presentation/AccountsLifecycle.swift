import SwiftUI

extension AccountsScreen {
    /// Runs the list's account additions and deletions and presents their errors.
    ///
    /// - Returns: The screen with managed additions and deletions.
    func accountsLifecycle() -> some View {
        modifier(AccountAdditionLifecycle(addition: addition).concat(AccountDeletionLifecycle(deletion: deletion)))
    }
}
