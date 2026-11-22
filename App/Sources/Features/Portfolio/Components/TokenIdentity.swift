import SwiftUI

/// A token's logo, symbol, and name.
///
/// The fonts follow the portfolio's layout. Cards show the name in spaced capitals.
struct TokenIdentity: View {
    @Environment(\.cardStyle.layout) private var layout
    let symbol: String
    let name: String
    let imageURL: URL?

    var body: some View {
        Label {
            Text(symbol)
                .font(layout == .cards ? .title3.bold() : .headline)
                .truncationMode(.middle)
            switch layout {
            case .cards:
                Text(name.localizedUppercase)
                    .font(.caption2.weight(.semibold))
                    .tracking(1.2)
                    .accessibilityLabel(name)
            case .rows:
                Text(name)
            }
        } icon: {
            TokenIcon(symbol: symbol, imageURL: imageURL)
        }
        .labelStyle(.subtitled)
    }
}
