import Foundation
import LocalAuthentication
import Security

/// A type that performs synchronous Keychain operations.
protocol KeychainAccessing: Sendable {
    /// Creates a new authentication context.
    ///
    /// - Returns: An unused context.
    func makeContext() -> LAContext

    /// Adds a Keychain item.
    ///
    /// - Parameter attributes: The item's identity, access control, and value.
    /// - Returns: The Security framework status code.
    func add(_ attributes: [String: Any]) -> OSStatus

    /// Reads the data of one matching item.
    ///
    /// - Parameter query: The query that identifies the item.
    /// - Returns: The Security framework status code and the item's data, if any.
    func copy(matching query: [String: Any]) -> (status: OSStatus, data: Data?)

    /// Deletes matching items.
    ///
    /// - Parameter query: The query that identifies the items.
    /// - Returns: The Security framework status code.
    func delete(matching query: [String: Any]) -> OSStatus
}

/// Keychain operations that call the Security framework.
struct SystemKeychain: KeychainAccessing {
    func makeContext() -> LAContext { LAContext() }

    func add(_ attributes: [String: Any]) -> OSStatus {
        SecItemAdd(attributes as CFDictionary, nil)
    }

    func copy(matching query: [String: Any]) -> (status: OSStatus, data: Data?) {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return (status, result as? Data)
    }

    func delete(matching query: [String: Any]) -> OSStatus {
        SecItemDelete(query as CFDictionary)
    }
}
