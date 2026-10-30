import SwiftUI

/// A button that adds an account or contact to Favorites or removes it.
struct FavoriteButton: View {
    @Environment(\.contactFavorite) private var contactFavorite
    let contact: Contact

    var body: some View {
        let title: LocalizedStringKey = contact.isFavorite ? "Remove from Favorites" : "Add to Favorites"
        Button {
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
