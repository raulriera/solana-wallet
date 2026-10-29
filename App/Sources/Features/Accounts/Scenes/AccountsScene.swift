import SwiftUI

/// Owns Settings > Accounts: its navigation, which pushes an account to rename or delete it, and the screens' changes.
///
/// Choosing an account shows it in the window and keeps this list open.
struct AccountsScene: View {
    @Environment(AccountStore.self) private var store
    @State private var path: [AccountsRoute] = []
    @State private var addition = AccountAdditionModel()
    @State private var rename = AccountRenameModel()
    @State private var deletion = AccountDeletionModel()
    /// The window's account, whose wallet's accounts are listed; choosing another changes it, and it can't be deleted
    /// while the window shows it.
    @Binding var account: Account

    var body: some View {
        let accounts = store.accounts(inWallet: account.recoveryID)
        NavigationStack(path: $path) {
            AccountsScreen(accounts: accounts, selection: $account, addition: addition, deletion: deletion, path: $path)
                .accountsLifecycle()
                .navigationDestination(for: AccountsRoute.self) { route in
                    switch route {
                    case .account(let id):
                        // The account as saved, so a rename from another window shows here too.
                        if let shown = accounts.first(where: { $0.id == id }) {
                            AccountScreen(account: shown, canDelete: shown.id != account.id, rename: rename,
                                          deletion: deletion)
                                .accountRenameLifecycle()
                        }
                    }
                }
        }
        // An account deleted in another window closes its screen here; deletions always change the count.
        .onChange(of: accounts.count) {
            let saved = Set(store.accounts(inWallet: account.recoveryID).map(\.id))
            path.removeAll { route in
                switch route {
                case .account(let id): !saved.contains(id)
                }
            }
        }
    }
}
