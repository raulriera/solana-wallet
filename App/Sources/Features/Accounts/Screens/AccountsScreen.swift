import Accessibility
import SwiftUI
import Transactions
import Wallet

/// Lists the accounts of the window's wallet and adds the wallet's next account.
struct AccountsScreen: View {
    @Environment(\.palette) private var palette
    /// The wallet's accounts, in the order they were added.
    let accounts: [Account]
    /// The window's wallet.
    let wallet: UUID
    /// The scene's additions.
    let addition: AccountAdditionModel
    /// The scene's deletions, which run here once an account's screen closes.
    let deletion: AccountDeletionModel

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
            .listRowBackground(palette.surface)

            Section {
                ForEach(accounts) { account in
                    NavigationLink(value: AccountsRoute.account(account.id)) {
                        RecipientRow(name: account.name, address: account.address, date: nil,
                                     systemImage: "wallet.bifold")
                    }
                }
            }
            .listRowBackground(palette.surface)
            .listRowSeparatorTint(palette.separator)

            Section {
                Button { addition.add(to: wallet) } label: {
                    HStack {
                        Text("Add Account")
                        Spacer()
                        if isAdding {
                            ProgressView()
                        }
                    }
                }
                .foregroundStyle(palette.accent)
                // Action rows stay one line at every text size; VoiceOver still reads the whole title.
                .lineLimit(1)
                .disabled(isAdding)
            } footer: {
                Text("Adding an account reads this wallet's recovery phrase, so you confirm it's you first.",
                     comment: "Footer under Add Account in Settings > Accounts. Adding asks for Face ID, Touch ID, or the passcode.")
                    .foregroundStyle(palette.secondaryText)
            }
            .listRowBackground(palette.surface)
        }
        // Rows only come and go here, so the count is a complete, cheap key: an added row slides in, a deleted one out.
        .animation(.default, value: accounts.count)
        .navigationTitle("Accounts")
        .navigationBarTitleDisplayMode(.inline)
        .foregroundStyle(palette.primaryText, palette.secondaryText)
        .scrollContentBackground(.hidden)
        .readableContentWidth()
        .background(palette.background)
        .sensoryFeedback(.success, trigger: addition.added)
        // Focus stays on Add Account, so VoiceOver hears which account the row below is.
        .onChange(of: addition.added) { _, added in
            guard let added else { return }
            AccessibilityNotification.Announcement(String(localized: "\(added.name) added",
                                                          comment: "VoiceOver announcement after adding an account. The variable is its name, such as Account 2.")).post()
        }
    }
}

#Preview {
    let wallet = UUID()
    NavigationStack {
        AccountsScreen(accounts: [
            Account(id: UUID(), recoveryID: wallet, address: try! Address("6d8tEyrqPqVbEr6Jpuc7BEyYekeMUTyzHEwdmcAYEmtK"),
                    path: .solana),
            Account(id: UUID(), recoveryID: wallet, address: try! Address("44korouVTkSZ4u3SAT4BCg5S2AqJTV7osjVGVkjs3vtV"),
                    path: .solana(account: 1), customName: "Savings"),
        ], wallet: wallet, addition: AccountAdditionModel(), deletion: AccountDeletionModel())
    }
}
