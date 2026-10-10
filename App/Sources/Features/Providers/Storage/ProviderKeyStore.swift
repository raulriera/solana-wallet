import Foundation

/// Device-only Keychain storage for the RPC provider's API key.
///
/// The key never synchronizes to iCloud or moves to another device. It can be read
/// whenever the device is unlocked, without biometric authentication.
nonisolated struct ProviderKeyStore: ProviderKeyStoring, KeyStoring {
    let service: String
    let account = "api-key"

    /// Creates storage in the app's Keychain access group.
    /// - Parameter service: A stable, app-specific namespace for the key's item.
    init(service: String) {
        self.service = service
    }

    /// Reads the saved key without user interaction.
    /// - Returns: The key, or `nil` before one is saved.
    /// - Throws: ``KeyStoreError`` or `CancellationError`.
    func key() async throws -> String? {
        guard let data = try await data() else { return nil }
        guard let key = String(data: data, encoding: .utf8) else { throw KeyStoreError.unreadable }
        return key
    }

    /// Saves a key, replacing any key already stored.
    ///
    /// Cancellation doesn't roll back a save that has already reached the Keychain.
    /// - Parameter key: A key the provider has already accepted.
    /// - Throws: ``KeyStoreError`` or `CancellationError`.
    func save(_ key: String) async throws {
        try await save(Data(key.utf8))
    }

    /// Deletes the saved key; a missing key is already deleted.
    /// - Throws: ``KeyStoreError`` or `CancellationError`.
    func deleteKey() async throws {
        try await delete()
    }
}
