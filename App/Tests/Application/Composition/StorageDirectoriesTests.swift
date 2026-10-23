import Foundation
import Testing
@testable import widgets

/// Verifies where the app keeps files that only a reset deletes, and files it can create again.
@Suite(.timeLimit(.minutes(1)))
struct StorageDirectoriesTests {
    /// Kept files live in Application Support, which the app keeps out of backups, and cached files in Caches.
    @Test
    func `Kept files stay in Application Support and cached files in Caches`() {
        #expect(URL.persistentDirectory.deletingLastPathComponent().standardizedFileURL
                == URL.applicationSupportDirectory.standardizedFileURL)
        #expect(URL.ephemeralDirectory.deletingLastPathComponent().standardizedFileURL
                == URL.cachesDirectory.standardizedFileURL)
    }
}
