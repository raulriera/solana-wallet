import Accessibility
import SwiftUI

/// Lists a wallet's accounts, selects one, and adds the wallet's next account.
struct AccountsScreen: View {
    let accounts: [Account]
    @Binding var selection: Account
    let addition: AccountAdditionModel
    let deletion: AccountDeletionModel
    @Binding var path: [AccountsRoute]

    var body: some View {
        let isAdding = addition.isAdding
        Form {
            Section {
                TitleCardContent(
                    title: "Accounts",
                    message: "Each account has its own address. All of them come from this wallet's recovery phrase.",
                    systemImage: "wallet.bifold.fill"
                )
            }

            Section {
                ForEach(accounts) { account in
                    AccountRow(account: account, selection: $selection, path: $path)
                }
            }

            Section {
                Button { addition.add(to: selection.recoveryID) } label: {
                    PendingLabel(title: "Add Account", isPending: isAdding)
                }
                .lineLimit(1)
                .disabled(isAdding)
            }
        }
        .formStyle(.choices(checkmark: .leading, descriptionSpacing: 2))
        .animation(.default, value: accounts.count)
        .navigationTitle("Accounts")
        .toolbarTitleDisplayMode(.inline)
        .sensoryFeedback(.success, trigger: addition.added)
        .onChange(of: addition.added) { _, added in
            guard let added else { return }
            AccessibilityNotification.Announcement(String(localized: "\(added.name) added",
                                                          comment: "VoiceOver announcement after adding an account. The variable is its name, such as Account 2.")).post()
        }
    }
}
