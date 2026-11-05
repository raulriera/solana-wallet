import SwiftUI

/// A custom RPC choice with confirmed swipe deletion.
struct CustomRPCRow: View {
    let url: URL
    let isSelected: Bool
    /// The RPC waiting for the person to confirm its deletion.
    @Binding var removal: URL?
    let actions: any RPCActions

    var body: some View {
        RPCRow(provider: .custom(url), isSelected: isSelected, actions: actions)
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                SwipeDeleteButton(removal: $removal, item: url)
            }
            .rpcDeletion(of: url, removal: $removal, actions: actions)
    }
}
