import SwiftUI

/// A title card with a token's logo, name, and symbol on Solana.
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
