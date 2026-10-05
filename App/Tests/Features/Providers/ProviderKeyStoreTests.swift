import Foundation
import Security
import Testing
@testable import widgets

/// Checks device-only provider key storage against the simulator's real Keychain.
@Suite(.timeLimit(.minutes(1)))
struct ProviderKeyStoreTests {
    /// Reading before any save reports a missing key rather than an error.
    /// - Throws: A Keychain failure.
    @Test
    func `Reading before any save finds no key`() async throws {
        let service = Self.isolatedService()
        defer { Self.removeItems(for: service) }

        #expect(try await ProviderKeyStore(service: service).key() == nil)
    }

    /// Saving again keeps only the newest key.
    /// - Throws: A Keychain failure.
    @Test
    func `Each save replaces the stored key`() async throws {
        let service = Self.isolatedService()
        defer { Self.removeItems(for: service) }
        let store = ProviderKeyStore(service: service)

        try await store.save("first-fixture-key")
        try #require(try await store.key() == "first-fixture-key")
        try await store.save("second-fixture-key")
        #expect(try await store.key() == "second-fixture-key")
    }

    /// The saved item never syncs through iCloud and isn't restored to another device.
    /// - Throws: A Keychain failure.
    @Test
    func `A saved key stays on this device`() async throws {
        let service = Self.isolatedService()
        defer { Self.removeItems(for: service) }
        try await ProviderKeyStore(service: service).save("fixture-key")

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

    /// Creates a Keychain namespace that no other test or app data uses.
    /// - Returns: A unique service identifier.
    private static func isolatedService() -> String {
        "widgetsTests.provider-key.\(UUID().uuidString)"
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
