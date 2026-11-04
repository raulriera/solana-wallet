import SwiftUI
import Transactions
import Wallet

/// Renames an account, shows its whole address and its path, and deletes it.
struct AccountScreen: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var isConfirmingDeletion = false
    let account: Account
    let canDelete: Bool
    let rename: AccountRenameModel
    let deletion: AccountDeletionModel

    /// Creates the screen of an account.
    ///
    /// - Parameters:
    ///   - account: The saved account.
    ///   - canDelete: Whether the account can be deleted.
    ///   - rename: The model that renames the account.
    ///   - deletion: The model that deletes the account.
    init(account: Account, canDelete: Bool, rename: AccountRenameModel, deletion: AccountDeletionModel) {
        self.account = account
        self.canDelete = canDelete
        self.rename = rename
        self.deletion = deletion
    }

    var body: some View {
        let isRenaming = rename.isRenaming
        Form {
            Section {
                TextField(text: $name) {
                    Text(account.defaultName)
                }
                .accessibilityLabel(Text("Name"))
                .submitLabel(.done)
                .onSubmit(save)
                .disabled(isRenaming)
            } header: {
                Text("Name", comment: "Header of an account's name field in Settings > Accounts.")
            } footer: {
                Text("Leave the name empty to use \(account.defaultName).",
                     comment: "Footer under an account's name field. The variable is its numbered name, such as Account 2.")
                    .foregroundStyle(palette.secondaryText)
            }

            FullAddressSection(address: account.address)

            Section {
                LabeledContent("Account Path") {
                    Text(verbatim: account.path.description)
                }
            }

            if canDelete {
                Section {
                    Button("Delete Account", systemImage: "trash", role: .destructive) { isConfirmingDeletion = true }
                        .labelStyle(.warning)
                        .lineLimit(1)
                        .disabled(isRenaming)
                        .confirmationDialog("Delete Account?", isPresented: $isConfirmingDeletion) {
                            Button("Delete Account", role: .destructive, action: delete)
                        } message: {
                            Text("\(account.name) will be removed from this device. Its funds stay at its address, and your recovery phrase can bring it back.",
                                 comment: "Message when deleting an account in Settings > Accounts. The variable is its name, such as Account 2.")
                        }
                }
            }
        }
        .confirmationAction("Save Name", isEnabled: canSave, isPending: isRenaming, action: save)
        .navigationTitle(account.name)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: account.customName, initial: true) { _, saved in
            name = saved ?? ""
        }
        .onChange(of: rename.isRenamed) { _, isRenamed in
            if isRenamed { dismiss() }
        }
    }

    private var canSave: Bool { name != account.customName ?? "" }

    /// Starts deleting the account and closes the screen.
    private func delete() {
        deletion.delete(account.id)
        dismiss()
    }

    /// Saves the typed name when it differs from the saved one.
    private func save() {
        guard canSave else { return }
        rename.rename(account.id, to: name)
    }
}

#Preview {
    if let address = try? Address("6d8tEyrqPqVbEr6Jpuc7BEyYekeMUTyzHEwdmcAYEmtK") {
        NavigationStack {
            AccountScreen(account: Account(id: UUID(), recoveryID: UUID(), address: address,
                                           path: .solana(account: 1)),
                          canDelete: true, rename: AccountRenameModel(), deletion: AccountDeletionModel())
        }
    }
}
