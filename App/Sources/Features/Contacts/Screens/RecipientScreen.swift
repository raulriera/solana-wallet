import SwiftUI
import Transactions

/// Shows an address in full and what it's saved as; saves it as a contact, edits, favorites, or deletes it.
///
/// Deleting the contact leaves the screen, unless a recent payment still lists the address.
struct RecipientScreen: View {
    @Environment(\.palette) private var palette
    @Environment(\.contactEntry) private var contactEntry
    let address: Address
    /// The addresses the account can pay, which say what the address is saved as.
    let lists: ContactLists
    /// The contact waiting for the person to confirm its deletion.
    @State private var removal: Contact?

    var body: some View {
        let saved = lists.saved(at: address)
        let contact = lists.contacts.first { $0.address == address }
        Form {
            FullAddressSection(address: address)

            Section {
                Group {
                    if let contact {
                        Button("Edit Contact", systemImage: "pencil") { contactEntry?(editing: contact) }
                    }
                    if let saved {
                        FavoriteButton(contact: saved)
                    } else {
                        AddContactButton(address: address)
                    }
                }
                .foregroundStyle(palette.accent)
                // Action rows stay one line at every text size; VoiceOver still reads the whole title.
                .lineLimit(1)
            }
            .listRowBackground(palette.surface)

            if let contact {
                Section {
                    Button("Delete Contact", systemImage: "trash", role: .destructive) { removal = contact }
                        .labelStyle(.warning)
                        .lineLimit(1)
                        .contactDeletion(of: contact, removal: $removal)
                }
                .listRowBackground(palette.surface)
            }
        }
        // Saving the address adds its rows; the favorite button animates its own change.
        .animation(.default, value: saved?.id)
        .scrollContentBackground(.hidden)
        .readableContentWidth()
        .background(palette.background)
        .navigationTitle(lists.recipient(for: address).title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
