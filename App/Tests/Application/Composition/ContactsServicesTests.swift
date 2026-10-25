import Foundation
import Storage
import Testing
@testable import widgets

/// Checks that Contacts keeps its recent payments in the directory it's given.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct ContactsServicesTests {
    /// The recent payments are saved as one file in the directory, which a reset deletes.
    @Test
    func `Recent payments are saved in the directory`() async throws {
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let services = ContactsServices(directory: directory)

        try await services.recents.update { $0 = ContactsFixtures.recents }

        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(files == ["recents.json"])
        let relaunched = ContactsServices(directory: directory)
        await relaunched.recents.load()
        #expect(relaunched.recents.value == ContactsFixtures.recents)
    }
}
