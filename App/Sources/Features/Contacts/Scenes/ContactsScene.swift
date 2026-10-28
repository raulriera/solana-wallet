import RPC
import SwiftUI

/// Owns the contacts tab for the window's account on the window's network.
///
/// The tab creates its contacts when it first appears, so a window that never opens the tab creates none, and
/// creates new ones for another account or network, which have other recent payments.
struct ContactsScene: View {
    /// The window's account, which payments leave from.
    let account: Account
    /// The window's network, whose recent payments are listed.
    let network: Network
    @Environment(ContactStore.self) private var store
    @Environment(AccountStore.self) private var accounts
    @Environment(TransactionStore.self) private var transactions
    @State private var contacts: ContactsModel?
    /// What ``contacts`` belong to, so the tab keeps them when it appears again for the same account and network.
    @State private var owner: Owner?

    var body: some View {
        // One container, so the change below attaches once instead of to each branch.
        ZStack {
            if let contacts {
                ContactsSplitView(contacts: contacts,
                                  sender: PaymentSender(account: account, network: network, transactions: transactions))
                    // New contacts start the selection and the payment over.
                    .id(ObjectIdentifier(contacts))
            } else {
                // Reading what's saved happens in the split view, so nothing shows until then instead of a flashing
                // empty state.
                Color.clear
            }
        }
        // The action also runs each time the tab appears again, so it creates contacts only for a new owner; new
        // contacts would start the split view over and lose its selection.
        .onChange(of: Owner(account: account, network: network), initial: true) { _, owner in
            guard owner != self.owner else { return }
            self.owner = owner
            contacts = ContactsModel(sendingAccount: owner.account, network: owner.network,
                                     accounts: accounts.accounts(inWallet: owner.account.recoveryID), store: store,
                                     transactions: transactions)
        }
    }

    /// What the contacts belong to: the account that pays, on the network whose recent payments are listed.
    private struct Owner: Equatable {
        let account: Account
        let network: Network
    }
}
