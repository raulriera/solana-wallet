import Foundation
import Testing
@testable import widgets

struct AddressBookTests {
    @Test func `Saving replaces a contact with the same identity`() {
        var book = AddressBook()
        var bruno = Contact(name: "bruno", address: ContactsFixtures.bruno)
        book.save(bruno)
        bruno.name = "Zed"

        book.save(bruno)

        #expect(book.contacts == [bruno])
    }

    @Test func `Deleting removes only that contact`() {
        var book = ContactsFixtures.addressBook
        let alice = book.contacts.first { $0.address == ContactsFixtures.alice }!

        book.delete(alice)
        book.delete(alice)

        #expect(book.contacts.map(\.address) == [ContactsFixtures.bruno])
    }

    @Test func `Favorites change for saved contacts and accounts`() {
        var book = ContactsFixtures.addressBook
        let bruno = book.contacts.first { $0.address == ContactsFixtures.bruno }!

        book.setFavorite(true, for: bruno)
        book.setFavorite(true, for: Contact(name: "Stranger", address: ContactsFixtures.stranger))
        book.setFavorite(false, forAccountAt: ContactsFixtures.savings)

        #expect(book.contacts.filter(\.isFavorite).map(\.name) == ["bruno", "Alice"])
        #expect(book.contacts.count == 2)
        #expect(book.favoriteAccounts.isEmpty)
    }

    @Test func `The book reads back as saved`() throws {
        let book = ContactsFixtures.addressBook

        #expect(try JSONDecoder().decode(AddressBook.self, from: JSONEncoder().encode(book)) == book)
    }
}
