import Portfolio
import SwiftUI

/// The token's More menu in the detail toolbar; it removes the token after the person confirms.
struct TokenActionsMenu: View {
    @Environment(\.dismiss) private var dismiss
    @State private var pending: Holding.Identity?
    /// The token the menu acts on.
    let token: Holding.Identity
    /// The token's symbol, which the confirmation names.
    let symbol: String
    /// The window's token removals, which remove the token the person confirmed.
    let removal: TokenRemovalModel

    var body: some View {
        Menu("More", systemImage: "ellipsis") {
            Button("Remove Token", systemImage: "trash", role: .destructive) { pending = token }
                // The menu's monochrome tint would color the symbol too; destructive items keep the system red.
                .tint(.red)
        }
        // Toolbar buttons keep the system's monochrome look; the theme's tint is for content.
        .tint(.primary)
        .alert("Remove \(symbol)?", item: $pending) { token in
            Button("Remove", role: .destructive) {
                removal.remove(token)
                // The token's details close: compact width goes back to the list; expanded width clears the selection.
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}
