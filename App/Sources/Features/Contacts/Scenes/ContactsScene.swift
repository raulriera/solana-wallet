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
    /// The recent payments that every window shares.
    let services: ContactsServices
    /// The window's portfolio, whose tokens with a balance the keypad pays with.
    let portfolio: any PortfolioCoordinating
    /// Every network's transaction coordinator, which windows share and payments are sent with.
    let transactions: NetworkTransactions
    @Environment(ContactStore.self) private var store
    @State private var contacts: ContactsModel?
    /// What ``contacts`` belong to, so the tab keeps them when it appears again for the same account and network.
    @State private var owner: Owner?

    var body: some View {
        // One container, so the change below attaches once instead of to each branch.
        ZStack {
            if let contacts {
                ContactsSplitView(contacts: contacts, portfolio: portfolio,
                                  sender: PaymentSender(account: account, network: network, transactions: transactions,
                                                        portfolio: portfolio))
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
            contacts = ContactsModel(sendingAccount: owner.account.address, wallet: owner.account.recoveryID,
                                     network: owner.network, store: store, services: services)
        }
    }

    /// What the contacts belong to: the account that pays, on the network whose recent payments are listed.
    private struct Owner: Equatable {
        let account: Account
        let network: Network
    }
}
