import Accessibility
import SwiftUI
import Transactions
import Wallet

/// Lists a wallet's accounts, selects one, and adds the wallet's next account.
struct AccountsScreen: View {
    @Environment(\.palette) private var palette
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
                    HStack {
                        Text("Add Account")
                        Spacer()
                        if isAdding {
                            ProgressView()
                        }
                    }
                }
                .foregroundStyle(palette.primary)
                .lineLimit(1)
                .disabled(isAdding)
            } footer: {
                Text("Adding an account reads this wallet's recovery phrase, so you confirm it's you first.",
                     comment: "Footer under Add Account in Settings > Accounts. Adding asks for Face ID, Touch ID, or the passcode.")
                    .foregroundStyle(palette.secondaryText)
            }
        }
        .formStyle(.choices(checkmark: .leading, descriptionSpacing: 2))
        .animation(.default, value: accounts.count)
        .navigationTitle("Accounts")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.success, trigger: addition.added)
        .onChange(of: addition.added) { _, added in
            guard let added else { return }
            AccessibilityNotification.Announcement(String(localized: "\(added.name) added",
                                                          comment: "VoiceOver announcement after adding an account. The variable is its name, such as Account 2.")).post()
        }
    }
}

#Preview {
    @Previewable @State var path: [AccountsRoute] = []
    let wallet = UUID()
    if let main = try? Address("6d8tEyrqPqVbEr6Jpuc7BEyYekeMUTyzHEwdmcAYEmtK"),
       let savings = try? Address("44korouVTkSZ4u3SAT4BCg5S2AqJTV7osjVGVkjs3vtV") {
        let first = Account(id: UUID(), recoveryID: wallet, address: main, path: .solana)
        NavigationStack(path: $path) {
            AccountsScreen(accounts: [
                first,
                Account(id: UUID(), recoveryID: wallet, address: savings, path: .solana(account: 1),
                        customName: "Savings"),
            ], selection: .constant(first), addition: AccountAdditionModel(), deletion: AccountDeletionModel(),
               path: $path)
        }
    }
}
