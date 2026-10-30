import RPC
import SwiftUI

/// Shows the Contacts tab of an account on a network.
struct ContactsScene: View {
    @State private var contacts = ContactsModel()
    /// The account that pays.
    let account: Account
    let network: Network

    var body: some View {
        ContactsSplitView(account: account, network: network, contacts: contacts)
    }
}
