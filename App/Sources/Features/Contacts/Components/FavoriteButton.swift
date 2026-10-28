import SwiftUI

/// Adds an account or contact to Favorites, or removes it.
struct FavoriteButton: View {
    @Environment(\.contactFavorite) private var contactFavorite
    /// The listed account or contact, marked when it's a favorite.
    let contact: Contact

    var body: some View {
        let title: LocalizedStringKey = contact.isFavorite ? "Remove from Favorites" : "Add to Favorites"
        Button {
            // The row moves between sections, which animates.
            withAnimation { contactFavorite?(!contact.isFavorite, for: contact) }
        } label: {
            Label {
                Text(title)
                    .contentTransition(.opacity)
            } icon: {
                Image(systemName: contact.isFavorite ? "star.slash" : "star")
                    .contentTransition(.symbolEffect(.replace))
            }
        }
    }
}
