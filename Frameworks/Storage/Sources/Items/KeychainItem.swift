import Dispatch
import Foundation
import Security

/// A value saved on this device as one Keychain item, such as a provider's API key.
///
/// The item never synchronizes to iCloud or moves to another device. It can be read whenever
/// the device is unlocked, without biometric authentication.
public struct KeychainItem<Coding: ValueCoding>: ValueStoring {
    /// Blocking Security work that runs only on the Keychain queue.
    private typealias Operation<Result: Sendable> = @Sendable () throws -> Result

    /// The stable, app-specific namespace that holds the item.
    public let service: String
    /// The item's name within its namespace.
    public let account: String
    /// How the value is kept as bytes.
    public let coding: Coding

    /// Names an item in the app's Keychain access group.
    /// - Parameters:
    ///   - service: The stable, app-specific namespace that holds the item.
    ///   - account: The item's name within its namespace.
    ///   - coding: How the value is kept as bytes, such as `.utf8`.
    public init(service: String, account: String, coding: Coding) {
        self.service = service
        self.account = account
        self.coding = coding
    }

    /// Reads the saved value without user interaction.
    /// - Returns: The value, or `nil` before one is saved.
    /// - Throws: ``KeychainItemError`` or `CancellationError`.
    public func load() async throws -> Coding.Value? {
        try await perform { [self] in try read() }
    }

    /// Saves a value, replacing any value already saved.
    ///
    /// A value whose bytes don't decode back to an equal value isn't saved, so a save never writes bytes that this coding can't read back.
    /// Cancellation doesn't roll back a save that has already reached the Keychain.
    /// - Parameter value: The new value.
    /// - Throws: ``KeychainItemError``, an encoding error, or `CancellationError`.
    public func save(_ value: Coding.Value) async throws {
        try await perform { [self] in try write(value) }
    }

    /// Deletes the saved value; a missing value is already deleted.
    /// - Throws: ``KeychainItemError`` or `CancellationError`.
    public func delete() async throws {
        try await perform { [self] in try remove() }
    }

    /// Reads, changes, and saves the value in one Keychain step, so changes made at the same time don't overwrite
    /// each other.
    ///
    /// A changed value whose bytes don't decode back to an equal value isn't saved. Cancellation doesn't roll back a
    /// change that has already reached the Keychain.
    /// - Parameter change: Changes the saved value, or `nil` before one is saved; setting `nil` deletes the value,
    ///   and an unchanged value isn't saved again.
    /// - Returns: The change's result.
    /// - Throws: The change's error, which keeps the saved value, ``KeychainItemError``, an encoding error, or
    ///   `CancellationError`.
    public func update<Result: Sendable>(
        _ change: @escaping @Sendable (inout Coding.Value?) throws -> Result
    ) async throws -> Result {
        try await perform { [self] in
            let saved = try read()
            var value = saved
            let result = try change(&value)
            guard value != saved else { return result }
            if let value { try write(value) } else { try remove() }
            return result
        }
    }

    /// Reads the saved value on the Keychain queue.
    /// - Returns: The value, or `nil` before one is saved.
    /// - Throws: ``KeychainItemError``.
    private func read() throws -> Coding.Value? {
        var query = identity
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        try check(status)
        guard let data = result as? Data, let value = coding.decode(data) else { throw KeychainItemError.unreadable }
        return value
    }

    /// Saves a value on the Keychain queue, replacing any value already saved, once its bytes decode back to it.
    /// - Parameter value: The new value.
    /// - Throws: ``KeychainItemError/unencodable`` before writing bytes that don't decode back to the value,
    ///   another ``KeychainItemError``, or an encoding error.
    private func write(_ value: Coding.Value) throws {
        let data = try coding.encode(value)
        guard coding.decode(data) == value else { throw KeychainItemError.unencodable }
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

    /// Deletes the saved value on the Keychain queue; a missing value is already deleted.
    /// - Throws: ``KeychainItemError``.
    private func remove() throws {
        let status = SecItemDelete(identity as CFDictionary)
        if status != errSecItemNotFound { try check(status) }
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
private func check(_ status: OSStatus) throws {
    guard status == errSecSuccess else { throw KeychainItemError.keychain(status: status) }
}

/// The serial queue that every Keychain item shares, so each save and each read-change-save runs atomically.
private enum KeychainQueue {
    static let shared = DispatchQueue(label: "KeychainItem.Keychain", qos: .userInitiated)
}
