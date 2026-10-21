import Foundation
import Testing
import Transactions
@testable import widgets

/// Checks how the contacts list sorts and groups addresses, and how it favorites and deletes.
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
