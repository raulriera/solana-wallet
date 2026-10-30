import Dispatch
import Foundation
import Security

/// A value saved as one Keychain item that never leaves this device.
public struct KeychainItem<Coding: ValueCoding>: ValueStoring {
    /// Blocking Security work that runs on the Keychain queue.
    private typealias Operation<Result: Sendable> = @Sendable () throws -> Result

    public let service: String
    public let account: String
    public let coding: Coding

    /// Creates an item in the app's Keychain access group.
    ///
    /// - Parameters:
    ///   - service: The stable, app-specific namespace that holds the item.
    ///   - account: The item's name within its namespace.
    ///   - coding: The coding that converts the value to bytes.
    public init(service: String, account: String, coding: Coding) {
        self.service = service
        self.account = account
        self.coding = coding
    }

    public func load() async throws -> Coding.Value? {
        try await perform { [self] in try read() }
    }

    public func save(_ value: Coding.Value) async throws {
        try await perform { [self] in try write(value) }
    }

    public func delete() async throws {
        try await perform { [self] in try remove() }
    }

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

    /// Reads the saved value.
    ///
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

    /// Writes a value after checking that its bytes decode back to it.
    ///
    /// - Parameter value: The new value.
    /// - Throws: ``KeychainItemError`` or an encoding error.
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

    /// Deletes the saved value if it exists.
    ///
    /// - Throws: ``KeychainItemError``.
    private func remove() throws {
        let status = SecItemDelete(identity as CFDictionary)
        if status != errSecItemNotFound { try check(status) }
    }

    /// The query attributes that identify the item.
    private var identity: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }

    /// Runs a blocking Keychain operation on the Keychain queue.
    ///
    /// - Parameter operation: The blocking Security work.
    /// - Returns: The operation's result.
    /// - Throws: The operation's error or `CancellationError`.
    private func perform<Result: Sendable>(_ operation: @escaping Operation<Result>) async throws -> Result {
        try Task.checkCancellation()
        return try await withCheckedThrowingContinuation { continuation in
            KeychainQueue.shared.async { continuation.resume(with: Swift.Result(catching: operation)) }
        }
    }
}

/// Throws an error for a Security status other than success.
///
/// - Parameter status: The Keychain operation's status.
/// - Throws: ``KeychainItemError/keychain(status:)`` if the status isn't success.
private func check(_ status: OSStatus) throws {
    guard status == errSecSuccess else { throw KeychainItemError.keychain(status: status) }
}

/// The serial queue that every Keychain item shares.
private enum KeychainQueue {
    static let shared = DispatchQueue(label: "KeychainItem.Keychain", qos: .userInitiated)
}
