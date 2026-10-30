import Foundation
import Storage
import Testing
@testable import widgets

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct ContactStoreTests {
    @Test
    func `Loading reads the saved address book`() async {
        let addressBook = StoredValue(ContactsFixtures.addressBook)
        let store = ContactsFixtures.store(addressBook)
        #expect(store.phase == .unloaded)
        #expect(await addressBook.loads == 0)

        await store.load()

        #expect(store.phase == .loaded)
        #expect(store.addressBook == ContactsFixtures.addressBook)
    }

    @Test
    func `Changes are saved to the address book`() async throws {
        let addressBook = StoredValue(ContactsFixtures.addressBook)
        let store = ContactsFixtures.store(addressBook)
        await store.load()
        let alice = try #require(store.addressBook.contacts.first { $0.address == ContactsFixtures.alice })
        let aaron = Contact(name: "Aaron", address: ContactsFixtures.stranger)
        var expected = ContactsFixtures.addressBook
        expected.save(aaron)
        expected.setFavorite(true, for: aaron)
        expected.delete(alice)
        expected.setFavorite(false, forAccountAt: ContactsFixtures.savings)

        try await store.save(aaron)
        try await store.setFavorite(true, for: aaron)
        try await store.delete(alice)
        try await store.setFavorite(false, forAccountAt: ContactsFixtures.savings)

        #expect(store.addressBook == expected)
        #expect(await addressBook.value == expected)
    }

    @Test
    func `Erasing forgets the contacts`() async throws {
        let addressBook = StoredValue(ContactsFixtures.addressBook)
        let store = ContactsFixtures.store(addressBook)
        await store.load()

        try await store.erase()

        #expect(store.addressBook == AddressBook())
        #expect(await addressBook.value == nil)
    }

    @Test
    func `The address book is saved in the directory`() async throws {
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ContactStore(directory: directory)
        let bruno = Contact(name: "bruno", address: ContactsFixtures.bruno)

        try await store.save(bruno)

        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["contacts.json"])
        let relaunched = ContactStore(directory: directory)
        await relaunched.load()
        #expect(relaunched.addressBook.contacts == [bruno])
    }
}
