import SwiftUI

/// A token's round logo, or the first letter of its symbol when it has no logo or the logo can't load.
struct TokenIcon: View {
    let symbol: String
    let imageURL: URL?

    var body: some View {
        AsyncImage(url: imageURL, transaction: Transaction(animation: .default)) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
            case .empty where imageURL != nil:
                Color.clear
            default:
                Text(symbol.prefix(1).uppercased())
                    .monogramIcon()
            }
        }
        .id(imageURL)
        .circularIcon(.fill.tertiary)
    }
}

#Preview {
    TokenIcon(symbol: "SOL", imageURL: nil)
}
