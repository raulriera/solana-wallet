import Portfolio
import SwiftUI

/// The token's More menu in the detail toolbar; it removes the token after the person confirms.
struct TokenActionsMenu: View {
    @State private var pending: Holding?
    /// The token the menu acts on.
    let token: Holding
    /// Removes the token the person confirmed.
    let remove: (Holding) -> Void

    var body: some View {
        Menu("More", systemImage: "ellipsis") {
            Button("Remove Token", systemImage: "trash", role: .destructive) { pending = token }
                // The menu's monochrome tint would color the symbol too; destructive items keep the system red.
                .tint(.red)
        }
        // Toolbar buttons keep the system's monochrome look; the theme's tint is for content.
        .tint(.primary)
        .alert("Remove \(token.displaySymbol)?", item: $pending) { token in
            Button("Remove", role: .destructive) { remove(token) }
            Button("Cancel", role: .cancel) {}
        }
    }
}
