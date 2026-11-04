import Portfolio
import SwiftUI

/// A More menu that removes a token after the person confirms.
struct TokenActionsMenu: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    @Environment(\.removeToken) private var removeToken
    @State private var pending: Holding.Identity?
    let token: Holding.Identity
    let symbol: String

    var body: some View {
        Menu("More", systemImage: "ellipsis") {
            Button("Remove Token", systemImage: "trash", role: .destructive) { pending = token }
                .tint(palette.destructive)
        }
        .tint(.primary)
        .alert("Remove \(symbol)?", item: $pending) { token in
            Button("Remove", role: .destructive) {
                removeToken?(token)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}
