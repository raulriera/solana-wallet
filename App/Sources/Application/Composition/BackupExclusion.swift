import Foundation

/// Excludes app storage from device backups.
nonisolated enum BackupExclusion {
    /// Creates a directory when needed and excludes it and its contents from device backups.
    ///
    /// - Parameter directory: The directory to exclude.
    /// - Throws: A file system error if the directory can't be created or marked.
    static func apply(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var directory = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
    }
}
