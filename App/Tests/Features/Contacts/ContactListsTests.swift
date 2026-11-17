import Foundation
import Testing
import Transactions
@testable import widgets

struct ContactListsTests {
    @Test func `Contacts sort by name`() {
        #expect(ContactsFixtures.lists.contacts.map(\.name) == ["Alice", "bruno"])
    }

    @Test func `Favorite accounts are marked`() {
        #expect(ContactsFixtures.lists.accounts.map(\.isFavorite) == [true])
    }

    @Test func `Favorites list accounts before contacts`() {
        #expect(ContactsFixtures.lists.favorites.map(\.name) == ["Savings", "Alice"])
    }

    @Test func `Recents leave out saved addresses`() {
        #expect(ContactsFixtures.lists.recents.map(\.address) == [ContactsFixtures.recent])
    }

    @Test func `The recipient context lists every address the person used and the paid ones`() {
        let context = ContactsFixtures.lists.recipientContext
        let known = Set(context.knownAddresses)
        #expect(known == [ContactsFixtures.sending, ContactsFixtures.savings, ContactsFixtures.alice,
                          ContactsFixtures.bruno, ContactsFixtures.recent])
        #expect(context.paidAddresses == [ContactsFixtures.alice, ContactsFixtures.recent])
    }

    @Test func `Saved addresses are found`() {
        let lists = ContactsFixtures.lists
        #expect(lists.saved(at: ContactsFixtures.alice)?.name == "Alice")
        #expect(lists.saved(at: ContactsFixtures.savings)?.name == "Savings")
        #expect(lists.saved(at: ContactsFixtures.recent) == nil)
    }

    @Test func `Only listed addresses have rows`() {
        let lists = ContactsFixtures.lists
        #expect([ContactsFixtures.savings, ContactsFixtures.alice, ContactsFixtures.recent].allSatisfy(lists.lists))
        #expect(!lists.lists(ContactsFixtures.stranger))
    }

    @Test func `A contact at an account's address keeps the account's row once deleted`() {
        let contact = Contact(name: "Old Savings", address: ContactsFixtures.savings)
        #expect(ContactsFixtures.lists.keepsRow(afterDeleting: contact))
    }
}
