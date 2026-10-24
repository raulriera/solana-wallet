import RPC
import SwiftUI
import Transactions

/// Owns the contacts tab: the addresses the window's account can pay in the sidebar, the keypad as the detail of the
/// selected one, and the sheet that enters a new recipient.
///
/// The keypad still uses sample tokens.
struct ContactsScene: View {
    @State private var contacts: ContactsModel
    /// Counts Try Again taps after the saved contacts couldn't be read.
    @State private var loadAttempt = 0
    /// The selected address; every row that lists it is highlighted, so it stays highlighted when it moves to
    /// another section, such as a favorite that's removed.
    @State private var selection: Address?
    @State private var columnVisibility = NavigationSplitViewVisibility.automatic
    @State private var preferredColumn = NavigationSplitViewColumn.sidebar
    /// The payment being typed; it stays when the person picks another recipient.
    @State private var payment = PaymentModel(tokens: PaymentToken.samples, currencyCode: "USD")
    /// The sheet that enters a new payment's recipient or saves a recent address as a contact.
    @State private var entry: RecipientEntryModel?

    private let services: ContactsServices

    /// Lists the addresses an account can pay, created once for the scene; the owner gives another account or
    /// network a new scene.
    /// - Parameters:
    ///   - account: The window's account, which payments leave from.
    ///   - network: The window's network, whose recent payments are listed.
    ///   - services: The saved contacts and recent payments that every window shares.
    init(account: Account, network: Network, services: ContactsServices) {
        contacts = ContactsModel(sendingAccount: account.address, wallet: account.recoveryID, network: network,
                                 services: services)
        self.services = services
    }

    var body: some View {
        let isEmpty = contacts.isEmpty && selection == nil
        // One container, so the presentations and changes below attach once instead of to each branch.
        ZStack {
            if contacts.isUnreadable {
                // Nothing saved is replaced, so the person can try again without losing contacts.
                UnavailableScreen(title: "Contacts Unavailable",
                                  message: "Your saved contacts couldn't be loaded. Try again.",
                                  systemImage: "exclamationmark.triangle") {
                    Button("Try Again") { loadAttempt += 1 }
                        .buttonStyle(.primary)
                }
            } else if !contacts.isLoaded {
                // A local read is quick, so nothing shows until it finishes instead of a flashing empty state.
                Color.clear
            } else if isEmpty {
                // With no one to list or pay, one screen spans the tab instead of an empty state in each column.
                UnavailableScreen(title: "No Contacts",
                                  message: "Paste an address to make your first payment. Name it to save it as a contact.",
                                  systemImage: "person.crop.circle") {
                    Button("New Payment", action: startPayment)
                        .buttonStyle(.primary)
                }
            } else {
                NavigationSplitView(columnVisibility: $columnVisibility, preferredCompactColumn: $preferredColumn) {
                    RecipientList(selection: $selection, contacts: contacts)
                    .navigationTitle("Contacts")
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            // Toolbar buttons keep the system's monochrome look; the theme's tint is for content.
                            Button("New Payment", systemImage: "plus", action: startPayment)
                                .tint(.primary)
                        }
                    }
                    .sidebarColumnWidth()
                } detail: {
                    if let selection {
                        RecipientPaymentStack(recipient: contacts.recipient(for: selection), payment: payment,
                                              context: contacts.recipientContext) {
                            RecipientScreen(address: selection, contacts: contacts, selection: $selection)
                        }
                        // Another recipient starts on the keypad, not on the previous one's details.
                            .id(selection)
                    } else {
                        // The sidebar's New Payment button starts a payment, so this screen has no action of its own.
                        UnavailableScreen(title: "No Recipient Selected",
                                          message: "Choose who to pay, or paste an address for a new payment.",
                                          systemImage: "person.crop.circle") {}
                        // Inline like the keypad, so a cleared selection leaves no empty large title.
                        .navigationBarTitleDisplayMode(.inline)
                    }
                }
                .navigationSplitViewStyle(.tabSection)
            }
        }
        .animation(.default, value: isEmpty)
        // Reads again after any window saves a change, or fails to, so every window shows what's saved.
        .task(id: [services.revision.value, loadAttempt]) { await contacts.load() }
        .errorAlert($contacts.error)
        // Rows and details open the sheet to save or edit a contact without holding it.
        .environment(\.contactEntry, ContactEntryAction(contacts: contacts, entry: $entry))
        .sheet(item: $entry) { RecipientEntrySheet(entry: $0) }
        // A new payment's recipient opens the keypad, and an edited address keeps paying the same contact; a new
        // contact keeps whatever is selected.
        .onChange(of: entry?.confirmation) { _, confirmation in
            guard let confirmation else { return }
            switch confirmation.purpose {
            case .payment:
                // An address that no row lists gets a New Payment row, which animates in.
                withAnimation { selection = confirmation.address }
                // A selection made in code doesn't close a sidebar that covers the keypad, so the keypad shows alone;
                // in wide windows this also hides the sidebar beside it until the person shows it again.
                columnVisibility = .detailOnly
                preferredColumn = .detail
            case .addContact:
                break
            case .edit(let contact):
                if selection == contact.address { selection = confirmation.address }
            }
        }
    }

    /// Opens the sheet that enters a new payment's recipient.
    private func startPayment() {
        entry = RecipientEntryModel(contacts: contacts)
    }
}
