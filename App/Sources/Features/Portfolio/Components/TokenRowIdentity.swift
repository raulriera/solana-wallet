import SwiftUI

/// A token row's logo, symbol, and name.
struct TokenRowIdentity: View {
    let symbol: String
    let name: String
    let imageURL: URL?

    var body: some View {
        Label {
            Text(symbol)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(name)
                .lineLimit(1)
        } icon: {
            TokenIcon(symbol: symbol, imageURL: imageURL)
        }
        .labelStyle(.subtitled)
    }
}
