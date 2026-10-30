import Foundation
import Testing
@testable import widgets

@Suite(.timeLimit(.minutes(1)))
struct BackupExclusionTests {
    @Test
    func `A missing directory is created and excluded from backups`() throws {
        let directory = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try BackupExclusion.apply(to: directory)
        #expect(try directory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
    }

    @Test
    func `Excluding an existing directory keeps its files`() throws {
        let directory = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("Accounts/accounts.json")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = Data("[]".utf8)
        try data.write(to: file)
        try BackupExclusion.apply(to: directory)
        try BackupExclusion.apply(to: directory)
        #expect(try directory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
        #expect(try Data(contentsOf: file) == data)
    }
}
