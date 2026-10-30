import Foundation
import Security
import Storage
import Testing

@Suite(.timeLimit(.minutes(1)))
struct KeychainItemTests {
    @Test
    func `Reading before any save finds no value`() async throws {
        let service = Self.isolatedService()
        defer { Self.removeItems(for: service) }

        #expect(try await Self.text(in: service).load() == nil)
    }

    @Test
    func `Each save replaces the saved value`() async throws {
        let service = Self.isolatedService()
        defer { Self.removeItems(for: service) }
        let item = Self.text(in: service)

        try await item.save("first-fixture-key")
        try #require(try await item.load() == "first-fixture-key")
        try await item.save("second-fixture-key")
        #expect(try await item.load() == "second-fixture-key")
    }

    @Test
    func `Deleting the value leaves none to read`() async throws {
        let service = Self.isolatedService()
        defer { Self.removeItems(for: service) }
        let item = Self.text(in: service)
        try await item.save("fixture-key")

        try await item.delete()
        try await item.delete()

        #expect(try await item.load() == nil)
    }

    @Test
    func `Saved bytes that aren't a value are unreadable`() async throws {
        let service = Self.isolatedService()
        defer { Self.removeItems(for: service) }
        try await Self.text(in: service).save("not a list")

        await #expect(throws: KeychainItemError.unreadable) {
            try await KeychainItem(service: service, account: "value", coding: .json([String].self)).load()
        }
    }

    @Test
    func `A value that doesn't decode back is never saved`() async throws {
        let service = Self.isolatedService()
        defer { Self.removeItems(for: service) }
        try await Self.text(in: service).save("fixture-key")
        let item = KeychainItem(service: service, account: "value", coding: UndecodableCoding())

        await #expect(throws: KeychainItemError.unencodable) { try await item.save("replacement") }

        #expect(try await Self.text(in: service).load() == "fixture-key")
    }

    @Test
    func `A change to a value that doesn't decode back is never saved`() async throws {
        let service = Self.isolatedService()
        defer { Self.removeItems(for: service) }
        let item = KeychainItem(service: service, account: "value", coding: UndecodableCoding())

        await #expect(throws: KeychainItemError.unencodable) { try await item.update { $0 = "fixture-key" } }

        #expect(try await Self.text(in: service).load() == nil)
    }

    @Test
    func `Items with different accounts in one service are separate`() async throws {
        let service = Self.isolatedService()
        defer { Self.removeItems(for: service) }
        let first = Self.text(in: service, account: "first")
        let second = Self.text(in: service, account: "second")
        try await first.save("first-value")
        try await second.save("second-value")

        try await first.delete()

        #expect(try await first.load() == nil)
        #expect(try await second.load() == "second-value")
    }

    @Test
    func `Changes made at the same time all apply`() async throws {
        let service = Self.isolatedService()
        defer { Self.removeItems(for: service) }
        let item = Self.text(in: service)

        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<20 {
                group.addTask { try await item.update { $0 = ($0 ?? "") + "x" } }
            }
            try await group.waitForAll()
        }

        #expect(try await item.load() == String(repeating: "x", count: 20))
    }

    @Test
    func `A change to no value deletes the saved value`() async throws {
        let service = Self.isolatedService()
        defer { Self.removeItems(for: service) }
        let item = Self.text(in: service)
        try await item.save("fixture-key")

        try await item.update { $0 = nil }

        #expect(try await item.load() == nil)
    }

    @Test
    func `A failed change keeps the saved value`() async throws {
        let service = Self.isolatedService()
        defer { Self.removeItems(for: service) }
        let item = Self.text(in: service)
        try await item.save("fixture-key")

        await #expect(throws: CocoaError(.fileWriteUnknown)) {
            try await item.update { value in
                value = "replacement"
                throw CocoaError(.fileWriteUnknown)
            }
        }

        #expect(try await item.load() == "fixture-key")
    }

    @Test
    func `A saved value stays on this device`() async throws {
        let service = Self.isolatedService()
        defer { Self.removeItems(for: service) }
        try await Self.text(in: service).save("fixture-key")

        var query = Self.items(for: service)
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitAll
        var result: CFTypeRef?
        try #require(SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess)
        let items = try #require(result as? [[String: Any]])
        let item = try #require(items.first)

        #expect(items.count == 1)
        #expect(item[kSecAttrAccessible as String] as? String == kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
        #expect(item[kSecAttrSynchronizable as String] as? Bool != true)
    }

    private static func text(in service: String, account: String = "value") -> KeychainItem<UTF8Coding> {
        KeychainItem(service: service, account: account, coding: .utf8)
    }

    private static func isolatedService() -> String {
        "widgetsTests.keychain-item.\(UUID().uuidString)"
    }

    private static func items(for service: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }

    private static func removeItems(for service: String) {
        let status = SecItemDelete(items(for: service) as CFDictionary)
        #expect(status == errSecSuccess || status == errSecItemNotFound)
    }
}

nonisolated private struct UndecodableCoding: ValueCoding {
    func encode(_ value: String) -> Data {
        Data(value.utf8)
    }

    func decode(_ data: Data) -> String? {
        nil
    }
}
