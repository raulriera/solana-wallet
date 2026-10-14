import RPC
import SwiftUI

/// Chooses the network that the owning window shows; other windows keep theirs.
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
            .listRowBackground(palette.surface)

            Section {
                NetworkRow(name: LocalizedStringResource("Mainnet",
                                                         comment: "A choice in Settings > Network: Solana's main network, where tokens have real value."),
                           network: .mainnet, selection: $network)
                NetworkRow(name: LocalizedStringResource("Devnet",
                                                         comment: "A choice in Settings > Network: Solana's test network, where tokens have no value."),
                           network: .devnet, selection: $network)
            } footer: {
                Text("Only this window changes.",
                     comment: "Footer under the Mainnet and Devnet choices in Settings > Network. Each app window has its own network.")
                    .foregroundStyle(palette.secondaryText)
            }
            .listRowBackground(palette.surface)
            .listRowSeparatorTint(palette.separator)
        }
        .navigationTitle("Network")
        .navigationBarTitleDisplayMode(.inline)
        .foregroundStyle(palette.primaryText, palette.secondaryText)
        .scrollContentBackground(.hidden)
        .readableContentWidth()
        .background(palette.background)
    }
}

#Preview {
    @Previewable @State var network = Network.mainnet
    NavigationStack {
        NetworkScreen(network: $network)
    }
}
