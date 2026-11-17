import SwiftUI
import Transactions

/// One token as a card: its logo, symbol, and name, with its value and 24-hour change on the trailing side.
struct TokenCard: View {
    @Environment(\.cardStyle) private var style
    @Environment(\.artworkColors) private var artworkColors
    @State private var logoColor: ArtworkColor?
    let symbol: String
    let name: String
    let balance: TokenAmount?
    /// The token's total value and its quote currency, or `nil` when either is unknown.
    let value: (total: Decimal, currency: String)?
    /// The price's 24-hour change as a fraction, or `nil` when unknown.
    let change: Decimal?
    let imageURL: URL?
    /// Whether the account also holds the token privately.
    var isHeldPrivately = false

    var body: some View {
        let tint = CardTint(logo: logoColor ?? .placeholder, colors: style.colors)
        let shape = RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
        let secondary: ReadableSecondary = .readableSecondary(tint.text, on: tint.textBackground)

        HStack(spacing: 12) {
            TokenCardIdentity(symbol: symbol, name: name, imageURL: imageURL, secondary: secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            TokenFigures(balance: balance, value: value, change: change, isHeldPrivately: isHeldPrivately)
                .foregroundStyle(tint.text, secondary)
                .fixedSize()
        }
        .fontDesign(style.fontDesign)
        .foregroundStyle(tint.text)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background {
            shape
                .fill(LinearGradient(colors: [tint.top, tint.bottom], startPoint: .top, endPoint: .bottom))
                .overlay { shape.strokeBorder(.white.opacity(0.7), lineWidth: 1) }
                .shadow(color: .black.opacity(0.18), radius: 6, y: -2)
                .padding(.bottom, -64)
        }
        .animation(.default, value: logoColor)
        .geometryGroup()
        .accessibilityElement(children: .combine)
        .task(id: imageURL) {
            var color: ArtworkColor?
            if let url = imageURL {
                color = await artworkColors?.color(for: url)
            }
            guard !Task.isCancelled else { return }
            logoColor = color
        }
    }
}

#Preview {
    VStack(spacing: 0) {
        TokenCard(symbol: "SOL", name: "Solana", balance: TokenAmount(lamports: 12_500_000_000),
                  value: (total: 2_075, currency: "USD"), change: Decimal(string: "0.0129"), imageURL: nil)
        TokenCard(symbol: "MYST", name: "Mystery Token", balance: TokenAmount(amount: 42, decimals: 0), value: nil,
                  change: nil, imageURL: nil)
    }
    .padding(.bottom, 24)
    .clipShape(PocketClip())
}
