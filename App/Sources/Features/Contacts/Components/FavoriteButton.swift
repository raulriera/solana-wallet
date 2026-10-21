import SwiftUI

/// Adds an account or contact to Favorites, or removes it.
struct FavoriteButton: View {
    let contact: Contact
    let contacts: ContactsModel

    var body: some View {
        let title: LocalizedStringKey = contact.isFavorite ? "Remove from Favorites" : "Add to Favorites"
        Button {
            withAnimation { contacts.toggleFavorite(contact) }
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
