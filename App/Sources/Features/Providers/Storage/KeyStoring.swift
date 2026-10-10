import Dispatch
import Foundation
import Security

/// Device-only Keychain storage for one item, such as a provider's API key.
///
/// A conforming store names its item; the default implementation reads, saves, and deletes it.
/// The item never synchronizes to iCloud or moves to another device. It can be read whenever
/// the device is unlocked, without biometric authentication.
nonisolated protocol KeyStoring: Sendable {
    /// The stable, app-specific namespace that holds the item.
    var service: String { get }
    /// The item's name within its namespace.
    var account: String { get }
}

nonisolated extension KeyStoring {
    /// Blocking Security work that runs only on the Keychain queue.
    private typealias Operation<Value: Sendable> = @Sendable () throws -> Value

    /// Reads the item without user interaction.
    /// - Returns: The item's data, or `nil` before any is saved.
    /// - Throws: ``KeyStoreError`` or `CancellationError`.
    func data() async throws -> Data? {
        try await perform {
            var query = identity
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            query[kSecReturnData as String] = true
            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            if status == errSecItemNotFound { return nil }
            try check(status)
            guard let data = result as? Data else { throw KeyStoreError.unreadable }
            return data
        }
    }

    /// Saves the item, replacing any data already stored.
    ///
    /// Cancellation doesn't roll back a save that has already reached the Keychain.
    /// - Parameter data: The complete new value.
    /// - Throws: ``KeyStoreError/keychain(status:)`` or `CancellationError`.
    func save(_ data: Data) async throws {
        try await perform {
            let value = [kSecValueData as String: data]
            switch SecItemUpdate(identity as CFDictionary, value as CFDictionary) {
            case errSecItemNotFound:
                var attributes = identity.merging(value) { $1 }
                attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
                try check(SecItemAdd(attributes as CFDictionary, nil))
            case let status:
                try check(status)
            }
        }
    }

    /// Deletes the item; a missing item is already deleted.
    /// - Throws: ``KeyStoreError/keychain(status:)`` or `CancellationError`.
    func delete() async throws {
        try await perform {
            let status = SecItemDelete(identity as CFDictionary)
            if status != errSecItemNotFound { try check(status) }
        }
    }

    /// The one non-synchronizing item that this store names.
    private var identity: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
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
            KeychainQueue.shared.async { continuation.resume(with: Result(catching: operation)) }
        }
    }
}

/// Converts a Security status into a value-free storage error.
/// - Parameter status: The Keychain operation's status.
/// - Throws: ``KeyStoreError/keychain(status:)`` for any status other than success.
nonisolated private func check(_ status: OSStatus) throws {
    guard status == errSecSuccess else { throw KeyStoreError.keychain(status: status) }
}

/// The serial queue that every key store shares, so each update-then-add save runs atomically.
nonisolated private enum KeychainQueue {
    static let shared = DispatchQueue(label: "KeyStoring.Keychain", qos: .userInitiated)
}
