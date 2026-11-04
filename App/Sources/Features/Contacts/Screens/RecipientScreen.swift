import SwiftUI
import Transactions

/// Shows an address in full and saves, edits, favorites, or deletes its contact.
struct RecipientScreen: View {
    @Environment(\.palette) private var palette
    @Environment(\.contactEntry) private var contactEntry
    let address: Address
    let lists: ContactLists
    /// The contact whose deletion waits for confirmation.
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
                .foregroundStyle(palette.primary)
                .lineLimit(1)
            }

            if let contact {
                Section {
                    Button("Delete Contact", systemImage: "trash", role: .destructive) { removal = contact }
                        .labelStyle(.warning)
                        .lineLimit(1)
                        .contactDeletion(of: contact, removal: $removal)
                }
            }
        }
        .animation(.default, value: saved?.id)
        .navigationTitle(lists.recipient(for: address).title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
