import SwiftUI

/// A token's logo, name, and symbol on Solana, as its details and the add-token preview introduce it.
struct TokenTitleCard: View {
    let symbol: String
    let name: String
    let logoURL: URL?

    var body: some View {
        TitleCardContent(title: "\(name)", message: "\(symbol) · Solana") {
            TokenIcon(symbol: symbol, imageURL: logoURL)
        }
    }
}
