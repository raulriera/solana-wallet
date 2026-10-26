import Foundation
@testable import Storage
import Testing

/// Checks file storage against the simulator's real file system.
@Suite(.timeLimit(.minutes(1)))
struct FileItemTests {
    /// Reading before any save reports a missing value rather than an error.
    @Test
    func `Reading before any save finds no value`() async throws {
        let directory = Self.isolatedDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(try await Self.text(in: directory).load() == nil)
    }

    /// Saving creates the directory, and saving again keeps only the newest value.
    @Test
    func `Each save replaces the saved value`() async throws {
        let directory = Self.isolatedDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let item = Self.text(in: directory)

        try await item.save("first")
        try #require(try await item.load() == "first")
        try await item.save("second")
        #expect(try await Self.text(in: directory).load() == "second")
    }

    /// Deleting leaves no value, and deleting again without one still succeeds.
    @Test
    func `Deleting the value leaves none to read`() async throws {
        let directory = Self.isolatedDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let item = Self.text(in: directory)
        try await item.save("saved")

        try await item.delete()
        try await item.delete()

        #expect(try await item.load() == nil)
    }

    /// A file that isn't a value is reported as unreadable, and the file stays as it was.
    @Test
    func `A file that isn't a value is unreadable and kept`() async throws {
        let directory = Self.isolatedDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try await Self.text(in: directory).save("not a list")
        let item = FileItem(url: directory.appending(path: "value"), coding: .json([String].self))

        await #expect(throws: FileItemError.unreadable) { try await item.load() }
        await #expect(throws: FileItemError.unreadable) { try await item.update { $0 = ["replaced"] } }
        #expect(try await Self.text(in: directory).load() == "not a list")
    }

    /// Changes made at the same time each read the result of the one before, so none is lost.
    @Test
    func `Updates made at the same time are all kept`() async throws {
        let directory = Self.isolatedDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let item = FileItem(url: directory.appending(path: "value"), coding: .json([Int].self))

        try await withThrowingTaskGroup(of: Void.self) { group in
            for number in 0..<20 {
                group.addTask { try await item.update { $0 = ($0 ?? []) + [number] } }
            }
            try await group.waitForAll()
        }

        #expect(try await item.load()?.sorted() == Array(0..<20))
    }

    /// Setting the value to `nil` in an update deletes the file.
    @Test
    func `An update to nil deletes the file`() async throws {
        let directory = Self.isolatedDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let item = Self.text(in: directory)
        try await item.save("saved")

        try await item.update { $0 = nil }

        #expect(!FileManager.default.fileExists(atPath: item.url.path))
    }

    /// A file item that names no protection is readable only while the device is unlocked.
    @Test
    func `A file item is completely protected by default`() {
        let item = FileItem(url: Self.isolatedDirectory().appending(path: "value"), coding: .utf8)

        #expect(item.protection == .complete)
    }

    /// Each protection class saves with its own write option. The simulator doesn't apply protection classes to files,
    /// so the check reads the option that each save writes with.
    /// - Parameters:
    ///   - protection: The item's protection.
    ///   - option: The write option that applies it.
    @Test(arguments: [
        (FileProtectionType.complete, Data.WritingOptions.completeFileProtection),
        (.completeUnlessOpen, .completeFileProtectionUnlessOpen),
        (.completeUntilFirstUserAuthentication, .completeFileProtectionUntilFirstUserAuthentication),
        (.completeWhenUserInactive, .completeFileProtectionWhenUserInactive),
        (.none, .noFileProtection),
    ])
    func `Each protection saves with its write option`(protection: FileProtectionType,
                                                       option: Data.WritingOptions) {
        #expect(Data.WritingOptions(protection) == option)
    }

    /// A file item with a protection other than the default saves and reads its value.
    @Test
    func `A file that stays readable while locked saves its value`() async throws {
        let directory = Self.isolatedDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let item = FileItem(url: directory.appending(path: "value"), coding: .utf8,
                            protection: .completeUntilFirstUserAuthentication)

        try await item.save("first")
        try await item.update { $0 = "second" }

        #expect(try await item.load() == "second")
    }

    /// Creates a directory path that no other test uses.
    /// - Returns: A missing directory inside the temporary directory.
    private static func isolatedDirectory() -> URL {
        URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    }

    /// Names a text file inside a test's directory.
    /// - Parameter directory: The test's directory.
    /// - Returns: The file item.
    private static func text(in directory: URL) -> FileItem<UTF8Coding> {
        FileItem(url: directory.appending(path: "value"), coding: .utf8)
    }
}
