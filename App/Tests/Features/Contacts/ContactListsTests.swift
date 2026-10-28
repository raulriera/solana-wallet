import Foundation
import Testing
import Transactions
@testable import widgets

/// Checks how the contacts lists sort and group addresses, and which addresses rules check against.
struct ContactListsTests {
    /// Contacts sort by name without regard to case.
    @Test func `Contacts sort by name`() {
        #expect(ContactsFixtures.lists.contacts.map(\.name) == ["Alice", "bruno"])
    }

    /// Accounts are marked as favorites from the address book.
    @Test func `Favorite accounts are marked`() {
        #expect(ContactsFixtures.lists.accounts.map(\.isFavorite) == [true])
    }

    /// Favorites list favorite accounts before favorite contacts.
    @Test func `Favorites list accounts before contacts`() {
        #expect(ContactsFixtures.lists.favorites.map(\.name) == ["Savings", "Alice"])
    }

    /// Recents list only unsaved addresses, since saved ones show under their names.
    @Test func `Recents leave out saved addresses`() {
        #expect(ContactsFixtures.lists.recents.map(\.address) == [ContactsFixtures.recent])
    }

    /// Rules check a recipient against every address the person used: accounts, contacts, and paid addresses.
    @Test func `The recipient context lists every address the person used`() {
        let known = Set(ContactsFixtures.lists.recipientContext.knownAddresses)
        #expect(known == [ContactsFixtures.sending, ContactsFixtures.savings, ContactsFixtures.alice,
                          ContactsFixtures.bruno, ContactsFixtures.recent])
    }

    /// The first-payment rule sees only the addresses the person paid.
    @Test func `The recipient context lists the paid addresses`() {
        #expect(ContactsFixtures.lists.recipientContext.paidAddresses == [ContactsFixtures.alice, ContactsFixtures.recent])
    }

    /// A saved address is found under its name; an unsaved one isn't.
    @Test func `Saved addresses are found`() {
        let lists = ContactsFixtures.lists
        #expect(lists.saved(at: ContactsFixtures.alice)?.name == "Alice")
        #expect(lists.saved(at: ContactsFixtures.savings)?.name == "Savings")
        #expect(lists.saved(at: ContactsFixtures.recent) == nil)
    }

    /// Accounts, contacts, and unsaved recents have rows; the sending account and unpaid strangers don't.
    @Test func `Only listed addresses have rows`() {
        let lists = ContactsFixtures.lists
        #expect([ContactsFixtures.savings, ContactsFixtures.alice, ContactsFixtures.recent].allSatisfy(lists.lists))
        #expect(!lists.lists(ContactsFixtures.stranger))
    }

    /// A contact saved at one of the wallet's accounts keeps the account's row once it's deleted.
    @Test func `A contact at an account's address keeps the account's row once deleted`() {
        let contact = Contact(name: "Old Savings", address: ContactsFixtures.savings)
        #expect(ContactsFixtures.lists.keepsRow(afterDeleting: contact))
    }
}
