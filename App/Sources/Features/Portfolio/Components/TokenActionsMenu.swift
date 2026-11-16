import SwiftUI
import Transactions

/// A More menu that removes a token after the person confirms.
struct TokenActionsMenu: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    @Environment(\.removeToken) private var removeToken
    @State private var pending: Address?
    let mint: Address
    let symbol: String

    var body: some View {
        Menu("More", systemImage: "ellipsis") {
            Button("Remove Token", systemImage: "trash", role: .destructive) { pending = mint }
                .tint(palette.destructive)
        }
        .tint(.primary)
        .confirmation("Remove \(symbol)?", action: "Remove", item: $pending, perform: remove)
    }

    /// Removes the token and closes its screen.
    ///
    /// - Parameter mint: The mint address of the token to remove.
    private func remove(_ mint: Address) {
        removeToken?(mint)
        dismiss()
    }
}
