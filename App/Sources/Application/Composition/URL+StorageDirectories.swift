import Foundation

extension URL {
    /// The directory for files the app keeps until the person resets it, such as accounts, themes, token lists, and
    /// contacts.
    ///
    /// It's inside the Application Support directory, which the app keeps out of device backups.
    nonisolated static var persistentDirectory: URL {
        applicationSupportDirectory.appending(path: "Persistent", directoryHint: .isDirectory)
    }

    /// The directory for files the app can create again, such as balances.
    ///
    /// It's inside the Caches directory, so the system may also delete it when storage runs low.
    nonisolated static var ephemeralDirectory: URL {
        cachesDirectory.appending(path: "Ephemeral", directoryHint: .isDirectory)
    }
}
