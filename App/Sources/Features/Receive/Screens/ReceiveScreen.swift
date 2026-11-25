import RPC
import SwiftUI
import Transactions

/// Shows an account's address as a QR code and as text, with a way to share it.
struct ReceiveScreen: View {
    let address: Address
    let network: Network

    var body: some View {
        Form {
            Section {
                QRCode(text: address.value)
                    .frame(maxWidth: 240)
                    .padding(24)
                    .background(.white, in: .rect(cornerRadius: 24))
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            } footer: {
                if network == .devnet {
                    Text("This address is on Devnet. Devnet tokens are for testing and have no monetary value.",
                         comment: "Footer under an account's QR code in a window on Devnet, Solana's test network.")
                }
            }

            Section("Address") {
                FullAddress(text: address.value)
                ShareLink(item: address.value)
                    .lineLimit(1)
            }
        }
        .navigationTitle("Receive")
        .toolbarTitleDisplayMode(.inline)
    }
}
