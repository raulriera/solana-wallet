import RPC
import SwiftUI
import Transactions

/// Presents the receive screen in its own navigation stack.
struct ReceiveSheet: View {
    let address: Address
    let network: Network

    var body: some View {
        NavigationStack {
            ReceiveScreen(address: address, network: network)
                .cancellationAction()
        }
        .limitedTextSize()
    }
}
