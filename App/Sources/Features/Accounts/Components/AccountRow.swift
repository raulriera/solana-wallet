import SwiftUI
import Transactions
import Wallet

/// One account of the window's wallet: a choice that shows it in the window, with a leading checkmark while the window
/// shows it, and an info button that opens it to rename or delete it.
struct AccountRow: View {
    @Environment(\.palette) private var palette
    let account: Account
    /// The account that the window shows, which choosing this one changes.
    @Binding var selection: Account
    /// The scene's pushed screens, which the info button opens the account's screen on.
    @Binding var path: [AccountsRoute]

    var body: some View {
        HStack {
            // A leading checkmark leaves the trailing edge to the info button.
            Button {
                selection = account
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.name)
                    ShortAddress(address: account.address)
                        .font(.subheadline)
                        .foregroundStyle(palette.secondaryText)
                }
            }
            .buttonStyle(.choice(isSelected: selection.id == account.id, placement: .leading))

            Button("More Info", systemImage: "info.circle") { path.append(.account(account.id)) }
                .labelStyle(.iconOnly)
                .foregroundStyle(palette.accent)
                // A borderless button handles its own taps, so the rest of the row stays the choice.
                .buttonStyle(.borderless)
        }
    }
}

#Preview {
    @Previewable @State var path: [AccountsRoute] = []
    if let address = try? Address("6d8tEyrqPqVbEr6Jpuc7BEyYekeMUTyzHEwdmcAYEmtK") {
        let account = Account(id: UUID(), recoveryID: UUID(), address: address, path: .solana)
        NavigationStack(path: $path) {
            Form {
                AccountRow(account: account, selection: .constant(account), path: $path)
            }
        }
    }
}
