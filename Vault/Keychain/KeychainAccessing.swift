import Foundation
import LocalAuthentication
import Security

/// The synchronous Security operations used by the storage service.
///
/// The service calls these methods on its background queue. Query dictionaries
/// and Core Foundation values stay within that operation.
protocol KeychainAccessing: Sendable {
    /// Creates an independent authentication context for one operation.
    /// - Returns: A new, unused context owned by the caller.
    func makeContext() -> LAContext

    /// Adds one protected item.
    /// - Parameter attributes: The item's identity, access control, and value.
    /// - Returns: The Security framework status code.
    func add(_ attributes: [String: Any]) -> OSStatus

    /// Reads the data for one matching item.
    /// - Parameter query: The exact item identity and authentication context.
    /// - Returns: The Security status and optional returned data.
    func copy(matching query: [String: Any]) -> (status: OSStatus, data: Data?)

    /// Deletes matching items.
    /// - Parameter query: The exact identity of the item to delete.
    /// - Returns: The Security framework status code.
    func delete(matching query: [String: Any]) -> OSStatus
}

/// A direct adapter to Apple's Keychain and authentication APIs.
struct SystemKeychain: KeychainAccessing {
    /// Creates an unused context so authentications aren't reused across operations.
    /// - Returns: A new authentication context.
    func makeContext() -> LAContext { LAContext() }

    /// Adds an item using the supplied protection policy.
    /// - Parameter attributes: The complete item attributes.
    /// - Returns: The result of `SecItemAdd`.
    func add(_ attributes: [String: Any]) -> OSStatus {
        SecItemAdd(attributes as CFDictionary, nil)
    }

    /// Requests authenticated data from the Keychain.
    /// - Parameter query: The exact query for one item.
    /// - Returns: The result of `SecItemCopyMatching` and its data, when available.
    func copy(matching query: [String: Any]) -> (status: OSStatus, data: Data?) {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return (status, result as? Data)
    }

    /// Deletes the item identified by the query.
    /// - Parameter query: The exact item identity.
    /// - Returns: The result of `SecItemDelete`.
    func delete(matching query: [String: Any]) -> OSStatus {
        SecItemDelete(query as CFDictionary)
    }
}
