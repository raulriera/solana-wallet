import Foundation
import Testing
@testable import widgets

@Suite(.timeLimit(.minutes(1)))
struct URLStorageDirectoriesTests {
    @Test
    func `Kept files stay in Application Support and cached files in Caches`() {
        #expect(URL.persistentDirectory.deletingLastPathComponent().standardizedFileURL
                == URL.applicationSupportDirectory.standardizedFileURL)
        #expect(URL.ephemeralDirectory.deletingLastPathComponent().standardizedFileURL
                == URL.cachesDirectory.standardizedFileURL)
    }
}
