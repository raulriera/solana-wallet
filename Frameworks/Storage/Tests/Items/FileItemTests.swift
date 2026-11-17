import Foundation
import Testing
@testable import Storage

@Suite(.timeLimit(.minutes(1)))
struct FileItemTests {
    @Test
    func `Reading before any save finds no value`() async throws {
        let directory = Self.isolatedDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(try await Self.text(in: directory).load() == nil)
    }

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

    @Test
    func `An update to nil deletes the file`() async throws {
        let directory = Self.isolatedDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let item = Self.text(in: directory)
        try await item.save("saved")

        try await item.update { $0 = nil }

        #expect(!FileManager.default.fileExists(atPath: item.url.path))
    }

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

    private static func isolatedDirectory() -> URL {
        URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    }

    private static func text(in directory: URL) -> FileItem<UTF8Coding> {
        FileItem(url: directory.appending(path: "value"), coding: .utf8)
    }
}
