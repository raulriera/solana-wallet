import Encoding
import Foundation
import Testing
import Transactions
import Wallet
@testable import widgets

/// Exercises account persistence with isolated directories and public metadata only.
@Suite(.timeLimit(.minutes(1)))
struct AccountStoreTests {
    /// Missing storage is an empty first launch and doesn't create files during a read.
    @Test
    func `Missing account storage loads an empty list without creating files`() async throws {
        let directory = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store: any AccountStoring = try AccountStore(directory: directory)
        #expect(try await store.load().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    /// Reloads the same ordered metadata through a new store and verifies the on-disk field boundary.
    @Test
    func `Saved account metadata survives reopening`() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store: any AccountStoring = try AccountStore(directory: directory)
        let first = try account(index: 0)
        let second = try account(index: 1, recoveryID: first.recoveryID)
        _ = try await store.add(first)
        let committed = try await store.add(second)
        let restored = try await AccountStore(directory: directory).load()
        #expect(committed.map(\.id) == [first.id, second.id])
        #expect(restored.map(\.id) == committed.map(\.id))
        #expect(restored.map(\.recoveryID) == [first.recoveryID, first.recoveryID])
        #expect(restored.map(\.address) == [first.address, second.address])
        #expect(restored.map(\.path) == [first.path, second.path])
        let records = try #require(JSONSerialization.jsonObject(with: Data(contentsOf:
            directory.appendingPathComponent("accounts.json"))) as? [[String: Any]])
        #expect(records.allSatisfy { Set($0.keys) == ["id", "recoveryID", "address", "path"] })
    }

    /// Simultaneous additions through separate instances cannot overwrite another window's accounts.
    @Test
    func `Concurrent additions retain every account`() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let recoveryID = UUID()
        let accounts = try (0..<16).map { try account(index: UInt32($0), recoveryID: recoveryID) }
        try await withThrowingTaskGroup(of: Void.self) { group in
            for account in accounts {
                group.addTask { _ = try await AccountStore(directory: directory).add(account) }
            }
            try await group.waitForAll()
        }
        let restored = try await AccountStore(directory: directory).load()
        #expect(Set(restored.map(\.id)) == Set(accounts.map(\.id)))
        #expect(restored.count == accounts.count)
    }

    /// Duplicate identities, addresses, and derivation slots must never replace saved metadata.
    /// - Parameter field: The existing identity reused by the proposed addition.
    @Test(arguments: ["id", "address", "path"])
    func `Duplicate account identities are rejected without changing storage`(_ field: String) async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try AccountStore(directory: directory)
        let first = try account(index: 0)
        let other = try account(index: 1, recoveryID: first.recoveryID)
        _ = try await store.add(first)
        let file = directory.appendingPathComponent("accounts.json")
        let original = try Data(contentsOf: file)
        let duplicate = Account(id: field == "id" ? first.id : other.id, recoveryID: first.recoveryID,
            address: field == "address" ? first.address : other.address,
            path: field == "path" ? first.path : other.path)
        await #expect(throws: AccountStoreError.duplicateAccount) { try await store.add(duplicate) }
        #expect(try Data(contentsOf: file) == original)
    }

    /// Corrupt or inconsistent records prevent both loading and additions without resetting the file.
    /// - Parameter corruption: The malformed storage condition.
    @Test(arguments: ["json", "address", "path", "duplicate", "missing field"])
    func `Unreadable account storage is preserved`(_ corruption: String) async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let stored = try account(index: 0)
        var record: [String: Any] = ["id": stored.id.uuidString, "recoveryID": stored.recoveryID.uuidString,
            "address": stored.address.value, "path": stored.path.description]
        switch corruption {
        case "address": record["address"] = "invalid"
        case "path": record["path"] = "m/44'/501'/2147483648'"
        case "missing field": record.removeValue(forKey: "recoveryID")
        default: break
        }
        let bytes = try corruption == "json" ? Data("not-json".utf8)
            : JSONSerialization.data(withJSONObject: corruption == "duplicate" ? [record, record] : [record])
        let file = directory.appendingPathComponent("accounts.json")
        try bytes.write(to: file)
        let store = try AccountStore(directory: directory)
        let next = try account(index: 1)
        let matchesError: @Sendable (any Error) -> Bool = { error in
            switch corruption {
            case "json":
                if case DecodingError.dataCorrupted = error { return true }
                return false
            case "address": return error as? Transactions.ValidationError == .invalidAddress
            case "path": return error as? DerivationPath.ValidationError == .invalidPath
            case "duplicate": return error as? AccountStoreError == .duplicateAccount
            case "missing field":
                guard case let DecodingError.keyNotFound(key, _) = error else { return false }
                return key.stringValue == "recoveryID"
            default: return false
            }
        }
        await #expect { try await store.load() } throws: { matchesError($0) }
        await #expect { try await store.add(next) } throws: { matchesError($0) }
        #expect(try Data(contentsOf: file) == bytes)
    }

    /// A directory or symbolic link in place of metadata must not be read or replaced.
    /// - Parameter symbolicLink: Whether the invalid file points at another local file.
    @Test(arguments: [false, true])
    func `Account storage rejects directories and symbolic links`(symbolicLink: Bool) async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("accounts.json")
        let target = directory.appendingPathComponent("unrelated.json")
        let bytes = Data("[]".utf8)
        try bytes.write(to: target)
        if symbolicLink {
            try FileManager.default.createSymbolicLink(at: file, withDestinationURL: target)
        } else {
            try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        }
        let store = try AccountStore(directory: directory)
        await #expect(throws: AccountStoreError.invalidStorage) { try await store.load() }
        await #expect(throws: AccountStoreError.invalidStorage) { try await store.add(account(index: 0)) }
        #expect(try Data(contentsOf: target) == bytes)
        let values = try file.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        #expect(symbolicLink ? values.isSymbolicLink == true : values.isDirectory == true)
    }

    /// A failed filesystem operation is surfaced while the obstructing file remains intact.
    @Test
    func `An obstructed storage directory is rejected without changing existing files`() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let obstruction = directory.appendingPathComponent("obstruction")
        let bytes = Data("existing file".utf8)
        try bytes.write(to: obstruction)
        let store = try AccountStore(directory: obstruction)
        let next = try account(index: 0)
        await #expect(throws: CocoaError.self) { try await store.add(next) }
        #expect(try Data(contentsOf: obstruction) == bytes)
    }

    /// Denying the atomic write preserves the previously readable account metadata.
    @Test
    func `A failed atomic write preserves saved account metadata`() async throws {
        let directory = try temporaryDirectory()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            try? FileManager.default.removeItem(at: directory)
        }
        let store = try AccountStore(directory: directory)
        let first = try account(index: 0)
        let next = try account(index: 1, recoveryID: first.recoveryID)
        _ = try await store.add(first)
        let file = directory.appendingPathComponent("accounts.json")
        let original = try Data(contentsOf: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o400], ofItemAtPath: file.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)

        // Reading and the existing-directory setup must still succeed before the denied write.
        try #require(try await store.load().map(\.id) == [first.id])
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try #require(!FileManager.default.isWritableFile(atPath: directory.path))
        try #require(!FileManager.default.isWritableFile(atPath: file.path))

        await #expect { try await store.add(next) } throws: { error in
            (error as? CocoaError)?.code == .fileWriteNoPermission
        }
        #expect(try Data(contentsOf: file) == original)
        #expect(try await AccountStore(directory: directory).load().map(\.id) == [first.id])
    }

    /// Already canceled callers cannot create an account or modify existing metadata.
    @Test
    func `Already cancelled additions preserve existing account storage`() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try AccountStore(directory: directory)
        _ = try await store.add(account(index: 0))
        let file = directory.appendingPathComponent("accounts.json")
        let original = try Data(contentsOf: file)
        let next = try account(index: 1)
        let (gate, continuation) = AsyncStream<Void>.makeStream()
        let operation = Task { @concurrent in
            for await _ in gate {}
            return try await store.add(next)
        }
        operation.cancel()
        continuation.finish()
        await #expect(throws: CancellationError.self) { try await operation.value }
        #expect(try Data(contentsOf: file) == original)
    }

    /// Resetting deletes every saved account, and repeating it on empty storage still succeeds.
    @Test
    func `Removing all accounts leaves empty storage`() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try AccountStore(directory: directory)
        let first = try account(index: 0)
        _ = try await store.add(first)
        _ = try await store.add(try account(index: 1, recoveryID: first.recoveryID))

        try await store.removeAll()
        try await store.removeAll()

        #expect(try await AccountStore(directory: directory).load().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("accounts.json").path))
    }

    /// The same recovery can retain two discovery families at the same account index.
    @Test
    func `Both discovery path families survive reopening and subsequent additions`() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try AccountStore(directory: directory)
        let first = try account(index: 0)
        let otherAddress = try account(index: 1)
        let second = try Account(id: UUID(), recoveryID: first.recoveryID,
            address: otherAddress.address, path: DerivationPath("m/44'/501'/0'"))
        _ = try await store.add(first)
        _ = try await store.add(second)
        let third = try account(index: 2, recoveryID: first.recoveryID)
        _ = try await AccountStore(directory: directory).add(third)
        let restored = try await store.load()
        #expect(restored.map(\.id) == [first.id, second.id, third.id])
        #expect(restored.map(\.path) == [first.path, second.path, third.path])
        #expect(restored.map(\.recoveryID).allSatisfy { $0 == first.recoveryID })
    }

    /// Creates an isolated filesystem location for one test.
    /// - Returns: A unique, empty temporary directory.
    /// - Throws: A filesystem error.
    private func temporaryDirectory() throws -> URL {
        let directory = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        return directory
    }

    /// Creates public-only metadata for a small test index without generating recovery material.
    /// - Parameters:
    ///   - index: A test index below 256, also used to construct a distinct valid address.
    ///   - recoveryID: The shared recovery identity to record.
    /// - Returns: A unique account identity with a syntactically valid address.
    /// - Throws: An address validation error.
    private func account(index: UInt32, recoveryID: UUID = UUID()) throws -> widgets.Account {
        Account(id: UUID(), recoveryID: recoveryID,
            address: try Address(Base58.encode(Array(repeating: UInt8(index), count: 32))), path: try DerivationPath("m/44'/501'/\(index)'/0'"))
    }
}
