import SwiftUI

/// A modifier that asks the person to confirm a custom RPC's deletion before deleting it.
private struct RPCDeletion: ViewModifier {
    @Environment(RPCStore.self) private var rpcStore
    /// The custom RPC whose deletion waits for confirmation.
    @Binding var removal: URL?
    /// The custom RPC that this view deletes.
    let url: URL
    let actions: any RPCActions

    func body(content: Content) -> some View {
        content
            .confirmation("Delete RPC?", action: "Delete", isPresented: $removal[isPresenting: url],
                          perform: { actions.remove(url) }) {
                let host = Text(RPCSettings.Provider.custom(url).name)
                if rpcStore.settings?.selection == .custom(url) {
                    Text("\(host) will be deleted from this device, and every window will switch to Solana's public RPC.",
                         comment: "The Delete RPC confirmation's message for the RPC in use. The variable is the RPC's host.")
                } else {
                    Text("\(host) will be deleted from this device.",
                         comment: "The Delete RPC confirmation's message. The variable is the RPC's host.")
                }
            }
    }
}

extension View {
    /// Asks the person to confirm a custom RPC's deletion before deleting it.
    ///
    /// - Parameters:
    ///   - url: The custom RPC that this view deletes.
    ///   - removal: The custom RPC whose deletion waits for confirmation.
    ///   - actions: The provider commands that delete the RPC.
    /// - Returns: The view with the deletion's confirmation.
    func rpcDeletion(of url: URL, removal: Binding<URL?>, actions: any RPCActions) -> some View {
        modifier(RPCDeletion(removal: removal, url: url, actions: actions))
    }
}
