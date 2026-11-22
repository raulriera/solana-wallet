import SwiftUI

/// A token card's logo, symbol, and name.
struct TokenCardIdentity: View {
    let symbol: String
    let name: String
    let imageURL: URL?
    /// The card's color for supporting text.
    let secondary: ReadableSecondary

    var body: some View {
        Label {
            Text(symbol)
                .font(.title3.bold())
                .lineLimit(1)
                .truncationMode(.middle)
            Text(name.localizedUppercase)
                .font(.caption2.weight(.semibold))
                .tracking(1.2)
                .lineLimit(1)
                .foregroundStyle(secondary)
                .accessibilityLabel(name)
        } icon: {
            TokenIcon(symbol: symbol, imageURL: imageURL)
        }
        .labelStyle(.subtitled)
    }
}
