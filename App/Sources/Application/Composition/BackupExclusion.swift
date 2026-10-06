import Foundation

/// Keeps app data on this device by excluding its storage from device backups.
nonisolated enum BackupExclusion {
    /// Creates the directory when needed and excludes it, with everything inside it, from device backups.
    ///
    /// The system treats the flag as guidance, so apply it on every launch.
    /// - Parameter directory: The app-owned directory to keep out of backups.
    /// - Throws: A filesystem error if the directory can't be created or marked.
    static func apply(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var directory = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
    }
}
