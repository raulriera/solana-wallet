import Portfolio
import SwiftUI

/// One token as a card: its logo, symbol, and name, with its value and 24-hour change on the trailing side.
///
/// The balance takes the value's place when the value is unknown. The card takes its color from the token's logo;
/// until the color loads, or when the logo has none, it takes the gray behind the letter placeholder.
struct TokenCard: View {
    @Environment(\.cardStyle) private var style
    @Environment(\.artworkColors) private var artworkColors
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var logoColor: ArtworkColor?
    let symbol: String
    let name: String
    let amount: Amount?
    /// The token's total value and its quote currency, or `nil` when either is unknown.
    let value: (total: Decimal, currency: String)?
    /// The price's 24-hour change as a fraction, or `nil` when unknown.
    let change: Decimal?
    let imageURL: URL?

    var body: some View {
        let tint = CardTint(logo: logoColor ?? .placeholder, colors: style.colors)
        let isStacked = typeSize.isAccessibilitySize
        let layout = isStacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 12))
        let shape = RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
        let secondary: ReadableSecondary = .readableSecondary(tint.text, on: tint.textBackground)

        layout {
            HStack(spacing: 12) {
                TokenIcon(symbol: symbol, imageURL: imageURL)
                    .overlay { Circle().strokeBorder(.white.opacity(0.8), lineWidth: 1.5) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(symbol)
                        .font(.title3.bold())
                        .truncationMode(.middle)
                    // Provider names aren't localized strings, so they're uppercased for the person's locale;
                    // VoiceOver reads them as written, not letter by letter.
                    Text(name.localizedUppercase)
                        .font(.caption2.weight(.semibold))
                        .tracking(1.2)
                        .foregroundStyle(secondary)
                        .accessibilityLabel(name)
                }
                .lineLimit(isStacked ? nil : 1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Large values and balances shorten, as in 10.2K, so the symbol and name keep their room.
            VStack(alignment: isStacked ? .leading : .trailing, spacing: 2) {
                if let value {
                    TokenValue(total: value.total, currency: value.currency, abbreviates: true)
                        .font(.title3.weight(.semibold))
                    if let change {
                        DayChangeLabel(change: change)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(secondary)
                    }
                } else {
                    TokenBalance(amount: amount, abbreviates: true)
                        .font(.title3.weight(.semibold))
                }
            }
            .monospacedDigit()
            .multilineTextAlignment(isStacked ? .leading : .trailing)
            .layoutPriority(1)
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
                // The face continues under the next card or into the pocket, so its bottom never shows.
                .padding(.bottom, -64)
        }
        .animation(.default, value: logoColor)
        // The card moves as one piece when it re-sorts, so its rolling numbers don't drift apart from it.
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
        TokenCard(symbol: "SOL", name: "Solana", amount: Amount(units: 12_500_000_000, decimals: 9),
                  value: (total: 2_075, currency: "USD"), change: Decimal(string: "0.0129"), imageURL: nil)
        TokenCard(symbol: "MYST", name: "Mystery Token", amount: Amount(units: 42, decimals: 0), value: nil,
                  change: nil, imageURL: nil)
    }
    .padding(.bottom, 24)
    .clipShape(PocketClip())
}
