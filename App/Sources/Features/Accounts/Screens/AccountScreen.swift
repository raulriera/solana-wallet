import SwiftUI
import Transactions
import Wallet

/// Renames an account, shows its whole address and its path, and deletes it.
///
/// The screen closes once its new name is saved, or as the person confirms its deletion.
struct AccountScreen: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var isConfirmingDeletion = false
    /// The account as saved.
    let account: Account
    /// Whether the account can be deleted: every account but the one the window shows.
    let canDelete: Bool
    /// The scene's renames.
    let rename: AccountRenameModel
    /// The scene's deletions, which the accounts list runs once this screen closes.
    let deletion: AccountDeletionModel

    /// Shows an account, whose name field follows its saved name.
    /// - Parameters:
    ///   - account: The account as saved.
    ///   - canDelete: Whether the account can be deleted: every account but the one the window shows.
    ///   - rename: The scene's renames.
    ///   - deletion: The scene's deletions, which the accounts list runs once this screen closes.
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
                // The placeholder is the numbered name, which VoiceOver would read as if it were typed.
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
            .listRowBackground(palette.surface)

            FullAddressSection(address: account.address)

            Section {
                LabeledContent("Account Path") {
                    Text(verbatim: account.path.description)
                }
            }
            .listRowBackground(palette.surface)

            if canDelete {
                Section {
                    Button("Delete Account", systemImage: "trash", role: .destructive) { isConfirmingDeletion = true }
                        .labelStyle(.warning)
                        // Action rows stay one line at every text size; VoiceOver still reads the whole title.
                        .lineLimit(1)
                        .disabled(isRenaming)
                        .confirmationDialog("Delete Account?", isPresented: $isConfirmingDeletion) {
                            Button("Delete Account", role: .destructive, action: delete)
                        } message: {
                            Text("\(account.name) will be removed from this device. Its funds stay at its address, and your recovery phrase can bring it back.",
                                 comment: "Message when deleting an account in Settings > Accounts. The variable is its name, such as Account 2.")
                        }
                }
                .listRowBackground(palette.surface)
            }
        }
        .foregroundStyle(palette.primaryText, palette.secondaryText)
        .scrollContentBackground(.hidden)
        .readableContentWidth()
        .confirmationAction("Save Name", isEnabled: canSave, isPending: isRenaming, action: save)
        .background(palette.background)
        .navigationTitle(account.name)
        .navigationBarTitleDisplayMode(.inline)
        // The field shows the saved name, or stays empty to show the numbered one, including a name saved in another
        // window.
        .onChange(of: account.customName, initial: true) { _, saved in
            name = saved ?? ""
        }
        .onChange(of: rename.isRenamed) { _, isRenamed in
            if isRenamed { dismiss() }
        }
    }

    /// Whether the typed name differs from the saved one; the store ignores the spaces around a name.
    private var canSave: Bool { name != account.customName ?? "" }

    /// Closes the screen and leaves the deletion to the accounts list, where the account's row then leaves in view.
    private func delete() {
        deletion.delete(account.id)
        dismiss()
    }

    /// Saves the typed name, unless it's the saved one.
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
