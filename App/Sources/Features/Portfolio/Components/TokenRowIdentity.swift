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
                .truncationMode(.middle)
            Text(name)
        } icon: {
            TokenIcon(symbol: symbol, imageURL: imageURL)
        }
        .labelStyle(.subtitled)
    }
}
