import SwiftUI
import Transactions
import Wallet

/// A row that selects an account, with a button that opens the account's screen.
struct AccountRow: View {
    let account: Account
    @Binding var selection: Account
    @Binding var path: [AccountsRoute]

    var body: some View {
        HStack {
            Button {
                selection = account
            } label: {
                Text(account.name)
                ShortAddress(address: account.address)
            }
            .checked(selection.id == account.id)

            Button(moreInfoAbout: "\(account.name)") { path.append(.account(account.id)) }
                .buttonStyle(.moreInfo)
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
            .formStyle(.choices(checkmark: .leading, descriptionSpacing: 2))
        }
    }
}
