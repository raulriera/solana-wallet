import SwiftUI
import Transactions
import Wallet

/// A row that selects an account, with a button that opens the account's screen.
struct AccountRow: View {
    @Environment(\.palette) private var palette
    let account: Account
    @Binding var selection: Account
    @Binding var path: [AccountsRoute]

    var body: some View {
        HStack {
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
