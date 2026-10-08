import SwiftUI

/// A token's round logo, or the first letter of its symbol when it has no logo or the logo can't load.
struct TokenIcon: View {
    @ScaledMetric(relativeTo: .headline) private var diameter = 40
    let symbol: String
    let imageURL: URL?

    var body: some View {
        // Logos rarely change, so a cached copy of any age is used before the provider is asked again.
        AsyncImage(request: imageURL.map { URLRequest(url: $0, cachePolicy: .returnCacheDataElseLoad) },
                   transaction: Transaction(animation: .default)) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
            case .empty where imageURL != nil:
                // Even a cached logo arrives a moment later, so a letter here would flash before it.
                Color.clear
            default:
                Text(symbol.prefix(1).uppercased())
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: diameter, height: diameter)
        .background(.fill.tertiary, in: .circle)
        .clipShape(.circle)
        .accessibilityHidden(true)
    }
}

#Preview {
    TokenIcon(symbol: "SOL", imageURL: nil)
}
