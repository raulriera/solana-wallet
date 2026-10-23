import Foundation
import Testing
import Transactions
@testable import widgets

/// Checks how the contacts list sorts and groups addresses, which addresses rules check against, and how it saves,
/// favorites, and deletes.
@MainActor
struct ContactsModelTests {
    /// The account payments leave from is never offered as a recipient.
    @Test func `The sending account isn't listed`() {
        #expect(ContactsFixtures.model().accounts.map(\.address) == [ContactsFixtures.savings])
    }

    /// Contacts sort by name without regard to case.
    @Test func `Contacts sort by name`() {
        #expect(ContactsFixtures.model().contacts.map(\.name) == ["Alice", "bruno"])
    }

    /// Favorites list favorite accounts before favorite contacts.
    @Test func `Favorites list accounts before contacts`() {
        #expect(ContactsFixtures.model().favorites.map(\.name) == ["Savings", "Alice"])
    }

    /// Recents list only unsaved addresses, since saved ones show under their names.
    @Test func `Recents leave out saved addresses`() {
        #expect(ContactsFixtures.model().recents.map(\.address) == [ContactsFixtures.recent])
    }

    /// Payments are kept newest first.
    @Test func `Payments are newest first`() {
        #expect(ContactsFixtures.model().payments.map(\.address) == [ContactsFixtures.alice, ContactsFixtures.recent])
    }

    /// Rules check a recipient against every address the person used: accounts, contacts, and paid addresses.
    @Test func `The recipient context lists every address the person used`() {
        let known = Set(ContactsFixtures.model().recipientContext.knownAddresses)
        #expect(known == [ContactsFixtures.sending, ContactsFixtures.savings, ContactsFixtures.alice,
                          ContactsFixtures.bruno, ContactsFixtures.recent])
    }

    /// The first-payment rule sees only the addresses the person paid.
    @Test func `The recipient context lists the paid addresses`() {
        #expect(ContactsFixtures.model().recipientContext.paidAddresses == [ContactsFixtures.alice, ContactsFixtures.recent])
    }

    /// A saved address is paid under its name; an unsaved one has none.
    @Test func `Recipients are named only when saved`() {
        let contacts = ContactsFixtures.model()
        #expect(contacts.recipient(for: ContactsFixtures.alice) == PaymentRecipient(address: ContactsFixtures.alice, name: "Alice"))
        #expect(contacts.recipient(for: ContactsFixtures.recent).name == nil)
    }

    /// A saved address is found under its name; an unsaved one isn't.
    @Test func `Saved addresses are found`() {
        let contacts = ContactsFixtures.model()
        #expect(contacts.saved(at: ContactsFixtures.alice)?.name == "Alice")
        #expect(contacts.saved(at: ContactsFixtures.savings)?.name == "Savings")
        #expect(contacts.saved(at: ContactsFixtures.recent) == nil)
    }

    /// Accounts, contacts, and unsaved recents have rows; the sending account and unpaid strangers don't.
    @Test func `Only listed addresses have rows`() {
        let contacts = ContactsFixtures.model()
        #expect([ContactsFixtures.savings, ContactsFixtures.alice, ContactsFixtures.recent].allSatisfy(contacts.lists))
        #expect(!contacts.lists(ContactsFixtures.sending))
        #expect(!contacts.lists(ContactsFixtures.stranger))
    }

    /// A new contact joins the list in name order.
    @Test func `Saving a new contact keeps the list sorted`() {
        let contacts = ContactsFixtures.model()
        contacts.save(Contact(name: "Aaron", address: ContactsFixtures.stranger))
        #expect(contacts.contacts.map(\.name) == ["Aaron", "Alice", "bruno"])
    }

    /// Saving a contact with an existing identity replaces it instead of adding another.
    @Test func `Saving an edited contact replaces it`() throws {
        let contacts = ContactsFixtures.model()
        var bruno = try #require(contacts.saved(at: ContactsFixtures.bruno))
        bruno.name = "Zed"
        contacts.save(bruno)
        #expect(contacts.contacts.map(\.name) == ["Alice", "Zed"])
    }

    /// Deleting a contact who was paid lists their address under Recents again.
    @Test func `Deleting a paid contact returns them to Recents`() throws {
        let contacts = ContactsFixtures.model()
        contacts.delete(try #require(contacts.contacts.first { $0.address == ContactsFixtures.alice }))
        #expect(contacts.contacts.map(\.address) == [ContactsFixtures.bruno])
        #expect(contacts.recents.map(\.address) == [ContactsFixtures.alice, ContactsFixtures.recent])
    }

    /// Accounts and contacts both join and leave Favorites.
    @Test func `Favorites toggle for accounts and contacts`() throws {
        let contacts = ContactsFixtures.model()
        contacts.toggleFavorite(try #require(contacts.accounts.first { $0.address == ContactsFixtures.savings }))
        contacts.toggleFavorite(try #require(contacts.contacts.first { $0.address == ContactsFixtures.bruno }))
        #expect(contacts.favorites.map(\.name) == ["Alice", "bruno"])
    }

    /// A wallet with only its sending account and no contacts or payments has no one to list.
    @Test func `A list without anyone else is empty`() {
        let contacts = ContactsModel(sendingAccount: ContactsFixtures.sending,
                                     accounts: [Contact(name: "Main", address: ContactsFixtures.sending)],
                                     contacts: [], payments: [])
        #expect(contacts.isEmpty)
    }
}
