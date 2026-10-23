import SwiftUI

/// Adds an account or contact to Favorites, or removes it.
struct FavoriteButton: View {
    /// Whether the account or contact is a favorite.
    @Binding var isFavorite: Bool

    var body: some View {
        let title: LocalizedStringKey = isFavorite ? "Remove from Favorites" : "Add to Favorites"
        Button {
            // The row moves between sections, which animates.
            withAnimation { isFavorite.toggle() }
        } label: {
            Label {
                Text(title)
                    .contentTransition(.opacity)
            } icon: {
                Image(systemName: isFavorite ? "star.slash" : "star")
                    .contentTransition(.symbolEffect(.replace))
            }
        }
    }
}
