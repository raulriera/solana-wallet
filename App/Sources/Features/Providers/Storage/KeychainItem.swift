import Dispatch
import Foundation
import Security

/// A value saved on this device as one Keychain item, such as a provider's API key.
///
/// The item never synchronizes to iCloud or moves to another device. It can be read whenever
/// the device is unlocked, without biometric authentication.
nonisolated struct KeychainItem<Coding: ValueCoding>: ValueStoring {
    /// Blocking Security work that runs only on the Keychain queue.
    private typealias Operation<Result: Sendable> = @Sendable () throws -> Result

    /// The stable, app-specific namespace that holds the item.
    let service: String
    /// The item's name within its namespace.
    let account: String
    /// How the value is kept as bytes.
    let coding: Coding

    /// Names an item in the app's Keychain access group.
    /// - Parameters:
    ///   - service: The stable, app-specific namespace that holds the item.
    ///   - account: The item's name within its namespace.
    ///   - coding: How the value is kept as bytes, such as `.utf8`.
    init(service: String, account: String, coding: Coding) {
        self.service = service
        self.account = account
        self.coding = coding
    }

    /// Reads the saved value without user interaction.
    /// - Returns: The value, or `nil` before one is saved.
    /// - Throws: ``KeychainItemError`` or `CancellationError`.
    func load() async throws -> Coding.Value? {
        let data: Data? = try await perform {
            var query = identity
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            query[kSecReturnData as String] = true
            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            if status == errSecItemNotFound { return nil }
            try check(status)
            guard let data = result as? Data else { throw KeychainItemError.unreadable }
            return data
        }
        guard let data else { return nil }
        guard let value = coding.decode(data) else { throw KeychainItemError.unreadable }
        return value
    }

    /// Saves a value, replacing any value already saved.
    ///
    /// Cancellation doesn't roll back a save that has already reached the Keychain.
    /// - Parameter value: The new value.
    /// - Throws: ``KeychainItemError``, an encoding error, or `CancellationError`.
    func save(_ value: Coding.Value) async throws {
        let data = try coding.encode(value)
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

    /// Deletes the saved value; a missing value is already deleted.
    /// - Throws: ``KeychainItemError`` or `CancellationError`.
    func delete() async throws {
        try await perform {
            let status = SecItemDelete(identity as CFDictionary)
            if status != errSecItemNotFound { try check(status) }
        }
    }

    /// The one non-synchronizing item that keeps this value.
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
    private func perform<Result: Sendable>(_ operation: @escaping Operation<Result>) async throws -> Result {
        try Task.checkCancellation()
        return try await withCheckedThrowingContinuation { continuation in
            KeychainQueue.shared.async { continuation.resume(with: Swift.Result(catching: operation)) }
        }
    }
}

/// Converts a Security status into a value-free storage error.
/// - Parameter status: The Keychain operation's status.
/// - Throws: ``KeychainItemError/keychain(status:)`` for any status other than success.
nonisolated private func check(_ status: OSStatus) throws {
    guard status == errSecSuccess else { throw KeychainItemError.keychain(status: status) }
}

/// The serial queue that every Keychain item shares, so each update-then-add save runs atomically.
nonisolated private enum KeychainQueue {
    static let shared = DispatchQueue(label: "KeychainItem.Keychain", qos: .userInitiated)
}
