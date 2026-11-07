import RPC
import SwiftUI

/// A screen that chooses the window's network.
struct NetworkScreen: View {
    @Environment(\.palette) private var palette
    @Binding var network: Network

    var body: some View {
        Form {
            Section {
                TitleCardContent(
                    title: "Network",
                    message: "Choose the Solana network for this window. Devnet is for testing: it uses test tokens and shows no prices.",
                    systemImage: "network"
                )
            }

            Section {
                NetworkRow(name: LocalizedStringResource("Mainnet",
                                                         comment: "A choice in Settings > Network: Solana's main network, where tokens have real value."),
                           network: .mainnet, selection: $network)
                NetworkRow(name: LocalizedStringResource("Devnet",
                                                         comment: "A choice in Settings > Network: Solana's test network, where tokens have no value."),
                           network: .devnet, selection: $network)
            } footer: {
                Text("Only this window switches. Other windows keep their network, and new windows open on Mainnet.",
                     comment: "Footer under the Mainnet and Devnet choices in Settings > Network. Each app window has its own network.")
                    .foregroundStyle(palette.secondaryText)
            }
        }
        .formStyle(.choices)
        .navigationTitle("Network")
        .toolbarTitleDisplayMode(.inline)
    }
}

#Preview {
    @Previewable @State var network = Network.mainnet
    NavigationStack {
        NetworkScreen(network: $network)
    }
}
