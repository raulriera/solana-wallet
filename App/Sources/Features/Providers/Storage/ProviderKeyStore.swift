import Dispatch
import Foundation
import Security

/// Device-only Keychain storage for the RPC provider's API key.
///
/// The item never synchronizes to iCloud or moves to another device. It can be read
/// whenever the device is unlocked, without biometric authentication.
nonisolated struct ProviderKeyStore: ProviderKeyStoring {
    /// Blocking Security work that runs only on the Keychain queue.
    private typealias Operation<Value: Sendable> = @Sendable () throws -> Value

    private let service: String
    /// One serial queue for every store value, so each update-then-add save runs atomically.
    private static let queue = DispatchQueue(label: "ProviderKeyStore.Keychain", qos: .userInitiated)

    /// Creates storage in the app's Keychain access group.
    /// - Parameter service: A stable, app-specific namespace for the key's item.
    init(service: String) {
        self.service = service
    }

    /// Reads the saved key without user interaction.
    /// - Returns: The key, or `nil` before one is saved.
    /// - Throws: ``ProviderKeyStoreError`` or `CancellationError`.
    func key() async throws -> String? {
        try await perform {
            var query = identity
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            query[kSecReturnData as String] = true
            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            if status == errSecItemNotFound { return nil }
            try Self.check(status)
            guard let data = result as? Data, let key = String(data: data, encoding: .utf8) else {
                throw ProviderKeyStoreError.unreadable
            }
            return key
        }
    }

    /// Saves a key, replacing any key already stored.
    ///
    /// Cancellation doesn't roll back a save that has already reached the Keychain.
    /// - Parameter key: A key the provider has already accepted.
    /// - Throws: ``ProviderKeyStoreError`` or `CancellationError`.
    func save(_ key: String) async throws {
        try await perform {
            let value = [kSecValueData as String: Data(key.utf8)]
            switch SecItemUpdate(identity as CFDictionary, value as CFDictionary) {
            case errSecItemNotFound:
                var attributes = identity.merging(value) { $1 }
                attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
                try Self.check(SecItemAdd(attributes as CFDictionary, nil))
            case let status:
                try Self.check(status)
            }
        }
    }

    /// Deletes the saved key; a missing key is already deleted.
    /// - Throws: ``ProviderKeyStoreError`` or `CancellationError`.
    func deleteKey() async throws {
        try await perform {
            let status = SecItemDelete(identity as CFDictionary)
            if status != errSecItemNotFound { try Self.check(status) }
        }
    }

    /// The one non-synchronizing item in this store's namespace.
    private var identity: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "api-key",
            kSecAttrSynchronizable as String: false,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }

    /// Runs a blocking Keychain operation outside Swift's cooperative executor.
    /// - Parameter operation: Security work whose queries stay on the Keychain queue.
    /// - Returns: The operation's result.
    /// - Throws: The operation's error, or `CancellationError` if canceled before it's scheduled.
    private func perform<Value: Sendable>(_ operation: @escaping Operation<Value>) async throws -> Value {
        try Task.checkCancellation()
        return try await withCheckedThrowingContinuation { continuation in
            Self.queue.async { continuation.resume(with: Result(catching: operation)) }
        }
    }

    /// Converts a Security status into a key-free storage error.
    /// - Parameter status: The Keychain operation's status.
    /// - Throws: ``ProviderKeyStoreError/keychain(status:)`` for any status other than success.
    private static func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else { throw ProviderKeyStoreError.keychain(status: status) }
    }
}
