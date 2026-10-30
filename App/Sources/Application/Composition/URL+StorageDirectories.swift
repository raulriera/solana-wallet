import Foundation

extension URL {
    /// The directory for files the app keeps until a reset.
    nonisolated static var persistentDirectory: URL {
        applicationSupportDirectory.appending(path: "Persistent", directoryHint: .isDirectory)
    }

    /// The directory for files the app can create again.
    nonisolated static var ephemeralDirectory: URL {
        cachesDirectory.appending(path: "Ephemeral", directoryHint: .isDirectory)
    }
}
