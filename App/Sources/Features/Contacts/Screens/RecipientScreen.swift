import SwiftUI
import Transactions

/// Shows an address in full and what it's saved as; saves it as a contact, edits, favorites, or deletes it.
///
/// Deleting the contact leaves the screen, unless a recent payment still lists the address.
struct RecipientScreen: View {
    @Environment(\.palette) private var palette
    @Environment(\.contactEntry) private var contactEntry
    let address: Address
    let contacts: ContactsModel
    /// The window's selected address, which deleting its contact clears.
    @Binding var selection: Address?
    /// The contact waiting for the person to confirm its deletion.
    @State private var removal: Contact?

    var body: some View {
        @Bindable var contacts = contacts
        let saved = contacts.saved(at: address)
        let contact = contacts.contacts.first { $0.address == address }
        Form {
            Section {
                // The whole address, which people can copy with a touch and hold.
                FullAddress(text: address.value)
                    .foregroundStyle(palette.primaryText)
            } header: {
                Text("Address")
            } footer: {
                Text("Touch and hold the address to copy it.")
                    .foregroundStyle(palette.secondaryText)
            }
            .listRowBackground(palette.surface)

            Section {
                Group {
                    if let contact {
                        Button("Edit Contact", systemImage: "pencil") { contactEntry?(editing: contact) }
                    }
                    if let saved {
                        FavoriteButton(isFavorite: $contacts[isFavorite: saved])
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
                        .contactDeletion($removal, from: contacts, selection: $selection)
                }
                .listRowBackground(palette.surface)
            }
        }
        .animation(.default, value: saved)
        .scrollContentBackground(.hidden)
        .readableContentWidth()
        .background(palette.background)
        .navigationTitle(contacts.recipient(for: address).title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
