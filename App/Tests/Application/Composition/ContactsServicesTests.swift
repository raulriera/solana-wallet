import Foundation
import Storage
import Testing
@testable import widgets

/// Checks that Contacts keeps its files in the directory it's given.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct ContactsServicesTests {
    /// The address book and recent payments are saved as two files in the directory, which a reset deletes.
    @Test
    func `Contacts files are saved in the directory`() async throws {
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let services = ContactsServices(directory: directory)

        try await services.addressBook.save(ContactsFixtures.addressBook)
        try await services.recents.save(ContactsFixtures.recents)

        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(Set(files) == ["contacts.json", "recents.json"])
        #expect(try await ContactsServices(directory: directory).addressBook.load() == ContactsFixtures.addressBook)
    }
}
