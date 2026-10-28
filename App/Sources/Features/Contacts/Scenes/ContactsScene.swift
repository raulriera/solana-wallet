import RPC
import SwiftUI

/// Owns a window's Contacts tab for an account on a network: its changes to contacts and favorites, which explain a
/// change that can't be saved.
///
/// The tab keeps its selection and payment while the person switches tabs; the window gives it a new identity for
/// another account or network, which have other recent payments, so it starts again with nothing selected.
struct ContactsScene: View {
    @State private var contacts = ContactsModel()
    /// The account payments leave from.
    let account: Account
    /// The network whose recent payments are listed and whose tokens pay.
    let network: Network

    var body: some View {
        ContactsSplitView(account: account, network: network, contacts: contacts)
    }
}
