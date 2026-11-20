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
    func `The address book is saved in the directory as version 1`() async throws {
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ContactStore(directory: directory)
        let bruno = Contact(name: "bruno", address: ContactsFixtures.bruno)

        try await store.save(bruno)

        let coding = VersionedJSONCoding<AddressBook>(version: 1, unusable: .unreadable)
        #expect(try coding.decode(Data(contentsOf: directory.appending(path: "contacts.json")))?.contacts == [bruno])
        let relaunched = ContactStore(directory: directory)
        await relaunched.load()
        #expect(relaunched.addressBook.contacts == [bruno])
    }

    @Test
    func `An address book file that can't be used is read as empty and replaced by the next save`() async throws {
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "contacts.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(#"{"version": 1, "value": "damaged"}"#.utf8).write(to: file)
        let store = ContactStore(directory: directory)
        let bruno = Contact(name: "bruno", address: ContactsFixtures.bruno)

        await store.load()
        #expect(store.phase == .loaded)
        #expect(store.addressBook == AddressBook())
        try await store.save(bruno)

        let coding = VersionedJSONCoding<AddressBook>(version: 1, unusable: .unreadable)
        #expect(try coding.decode(Data(contentsOf: file))?.contacts == [bruno])
    }
}
