import Foundation
import Security
import Testing
@testable import widgets

/// Checks device-only value storage against the simulator's real Keychain.
@Suite(.timeLimit(.minutes(1)))
struct KeychainItemTests {
    /// Reading before any save reports a missing value rather than an error.
    /// - Throws: A Keychain failure.
    @Test
    func `Reading before any save finds no value`() async throws {
        let service = Self.isolatedService()
        defer { Self.removeItems(for: service) }

        #expect(try await Self.text(in: service).load() == nil)
    }

    /// Saving again keeps only the newest value.
    /// - Throws: A Keychain failure.
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

    /// Deleting leaves no value, and deleting again without one still succeeds.
    /// - Throws: A Keychain failure.
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

    /// Saved bytes that the item's coding can't read are reported as unreadable instead of becoming a value.
    /// - Throws: A Keychain failure.
    @Test
    func `Saved bytes that aren't a value are unreadable`() async throws {
        let service = Self.isolatedService()
        defer { Self.removeItems(for: service) }
        try await KeychainItem(service: service, account: "value", coding: ByteCoding()).save(Data([0xFF, 0xFE]))

        await #expect(throws: KeychainItemError.unreadable) { try await Self.text(in: service).load() }
    }

    /// Items with different accounts share a namespace without touching each other.
    /// - Throws: A Keychain failure.
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

    /// The saved item never syncs through iCloud and isn't restored to another device.
    /// - Throws: A Keychain failure.
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

    /// Names a text item in a test's namespace.
    /// - Parameters:
    ///   - service: The test's isolated namespace.
    ///   - account: The item's name.
    /// - Returns: An item that keeps text as UTF-8.
    private static func text(in service: String, account: String = "value") -> KeychainItem<UTF8Coding> {
        KeychainItem(service: service, account: account, coding: .utf8)
    }

    /// Creates a Keychain namespace that no other test or app data uses.
    /// - Returns: A unique service identifier.
    private static func isolatedService() -> String {
        "widgetsTests.keychain-item.\(UUID().uuidString)"
    }

    /// Matches every item in a test's namespace, whether or not it synchronizes.
    /// - Parameter service: The test's isolated namespace.
    /// - Returns: The base Keychain query for that namespace.
    private static func items(for service: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }

    /// Deletes this test's items so the simulator Keychain keeps no fixtures.
    /// - Parameter service: The test's isolated namespace.
    private static func removeItems(for service: String) {
        let status = SecItemDelete(items(for: service) as CFDictionary)
        #expect(status == errSecSuccess || status == errSecItemNotFound)
    }
}

/// Keeps bytes unchanged, so a test can save bytes that another coding can't read.
private struct ByteCoding: ValueCoding {
    /// Keeps the bytes as they are.
    /// - Parameter value: The bytes to save.
    /// - Returns: The same bytes.
    func encode(_ value: Data) -> Data { value }

    /// Returns the kept bytes as they are.
    /// - Parameter data: The kept bytes.
    /// - Returns: The same bytes.
    func decode(_ data: Data) -> Data? { data }
}
