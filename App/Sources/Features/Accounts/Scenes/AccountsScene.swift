import SwiftUI

/// Shows a wallet's accounts and the screens that rename or delete them.
struct AccountsScene: View {
    @Environment(AccountStore.self) private var store
    @State private var path: [AccountsRoute] = []
    @State private var addition = AccountAdditionModel()
    @State private var rename = AccountRenameModel()
    @State private var deletion = AccountDeletionModel()
    /// The account that the window shows.
    @Binding var account: Account

    var body: some View {
        let accounts = store.accounts(inWallet: account.recoveryID)
        NavigationStack(path: $path) {
            AccountsScreen(accounts: accounts, selection: $account, addition: addition, deletion: deletion, path: $path)
                .accountsLifecycle()
                .navigationDestination(for: AccountsRoute.self) { route in
                    switch route {
                    case .account(let id):
                        if let shown = accounts.first(where: { $0.id == id }) {
                            AccountScreen(account: shown, canDelete: shown.id != account.id, rename: rename,
                                          deletion: deletion)
                                .accountRenameLifecycle()
                        }
                    }
                }
        }
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
