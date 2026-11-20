import SwiftUI
import Transactions

/// Loads the addresses an account can pay and shows them in its content, with the sheet that enters a new one.
struct ContactsContainer<Content: View>: View {
    @Environment(ContactStore.self) private var store
    @Environment(RecentPaymentStore.self) private var recents
    @Binding var selection: Address?
    let lists: ContactLists
    @Bindable var contacts: ContactsModel
    /// The recipient sheet's model, or `nil` when the sheet is closed.
    @Binding var entry: RecipientEntryModel?
    let content: Content
    /// The number of Try Again taps.
    @State private var loadAttempt = 0

    /// Creates a container that loads the addresses an account can pay.
    ///
    /// - Parameters:
    ///   - selection: The address to pay.
    ///   - lists: The addresses the account can pay.
    ///   - contacts: The model that loads the lists and saves changes to them.
    ///   - entry: The recipient sheet's model, or `nil` when the sheet is closed.
    ///   - content: The view that lists the addresses, shown once there is one to list.
    init(selection: Binding<Address?>, lists: ContactLists, contacts: ContactsModel,
         entry: Binding<RecipientEntryModel?>, @ViewBuilder content: () -> Content) {
        _selection = selection
        self.lists = lists
        self.contacts = contacts
        _entry = entry
        self.content = content()
    }

    var body: some View {
        let isEmpty = lists.isEmpty && selection == nil
        ZStack {
            if lists.isUnreadable {
                UnavailableScreen(title: "Contacts Unavailable",
                                  message: "Your saved contacts couldn't be loaded. Try again.",
                                  systemImage: "exclamationmark.triangle") {
                    Button("Try Again") { loadAttempt += 1 }
                        .buttonStyle(.primary)
                }
            } else if isEmpty, !lists.isLoaded {
                Color.clear
            } else if isEmpty {
                UnavailableScreen(title: "No Contacts",
                                  message: "Paste an address to make your first payment. Name it to save it as a contact.",
                                  systemImage: "person.crop.circle") {
                    Button("New Payment") { entry = RecipientEntryModel() }
                        .buttonStyle(.primary)
                }
            } else {
                content
            }
        }
        .animation(.default, value: isEmpty)
        .task(id: loadAttempt) {
            await contacts.load(from: store, recents: recents)
        }
        .alert(error: $contacts.error)
        .environment(\.contactEntry, ContactEntryAction(lists: lists, entry: $entry))
        .environment(\.contactFavorite, ContactFavoriteAction(contacts: contacts, lists: lists, store: store))
        .environment(\.contactDeletion,
                     ContactDeletionAction(contacts: contacts, lists: lists, store: store, selection: $selection))
        .sheet(item: $entry) { RecipientEntrySheet(entry: $0, lists: lists) }
        .onChange(of: entry?.confirmation) { _, confirmation in
            guard let confirmation else { return }
            if let contact = confirmation.contact { contacts.save(contact, in: store) }
            switch confirmation.purpose {
            case .payment:
                withAnimation { selection = confirmation.address }
            case .addContact:
                break
            case .edit(let contact):
                if selection == contact.address { selection = confirmation.address }
            }
        }
    }
}
