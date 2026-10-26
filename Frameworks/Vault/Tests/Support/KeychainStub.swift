import Foundation
import LocalAuthentication
import Security
import Synchronization
@testable import Vault

// swift-format-ignore: NeverForceUnwrap
// The production queries always carry these values; a missing one is a test bug that stops the run.
/// A per-test Keychain that records protection and simulates Security results.
final class KeychainStub: KeychainAccessing {
    /// The service and account used to scope a stored item.
    struct Identity: Hashable {
        let service: String
        let account: String
    }

    /// Recorded data and outcomes, synchronized across the test and Keychain queue.
    struct State {
        var items: [Identity: Data] = [:]
        var readStatus: OSStatus = errSecSuccess
        var dataOverride: Data?
        var hasRequiredProtection = false
        var queriedOnlyLocalItems = true
        var ranOffMainThread = true
        var promptReasons: [String] = []
        var hidesPasscode = false
        var reusesUnlock = false
        var readCount = 0
    }

    let state = Mutex(State())
    private let contextFactory: @Sendable () -> LAContext
    private let beforeRead: @Sendable () -> Void

    /// Creates isolated storage with optional authentication and blocking controls.
    /// - Parameters:
    ///   - contextFactory: A fresh context factory for cancellation verification.
    ///   - beforeRead: A synchronous hook running only on the background Keychain queue.
    init(
        contextFactory: @escaping @Sendable () -> LAContext = { TestContext() },
        beforeRead: @escaping @Sendable () -> Void = {}
    ) {
        self.contextFactory = contextFactory
        self.beforeRead = beforeRead
    }

    /// Creates an independent context for an operation.
    /// - Returns: The context supplied by this test's factory.
    func makeContext() -> LAContext { contextFactory() }

    /// Inserts data without overwriting an existing item and checks the protection policy.
    /// - Parameter attributes: The production add query.
    /// - Returns: Success or a duplicate status.
    func add(_ attributes: [String: Any]) -> OSStatus {
        let identity = identity(in: attributes)
        let expected = SecAccessControlCreateWithFlags(
            nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, .userPresence, nil
        )!
        let access = attributes[kSecAttrAccessControl as String] as CFTypeRef?
        let protected = access.map { CFEqual($0, expected) } ?? false
        return state.withLock {
            $0.hasRequiredProtection = protected
            guard $0.items[identity] == nil else { return errSecDuplicateItem }
            $0.items[identity] = attributes[kSecValueData as String] as? Data
            return errSecSuccess
        }
    }

    /// Returns one stored payload or the configured failure without mutating storage.
    /// - Parameter query: The production read query.
    /// - Returns: The configured status and matching data.
    func copy(matching query: [String: Any]) -> (status: OSStatus, data: Data?) {
        let identity = identity(in: query)
        let context = query[kSecUseAuthenticationContext as String] as! LAContext
        state.withLock {
            $0.promptReasons.append(context.localizedReason)
            $0.hidesPasscode = $0.hidesPasscode || context.localizedFallbackTitle == ""
            $0.reusesUnlock = $0.reusesUnlock || context.touchIDAuthenticationAllowableReuseDuration != 0
            $0.readCount += 1
        }
        beforeRead()
        return state.withLock {
            guard $0.readStatus == errSecSuccess else { return ($0.readStatus, nil) }
            guard let data = $0.dataOverride ?? $0.items[identity] else { return (errSecItemNotFound, nil) }
            return (errSecSuccess, data)
        }
    }

    /// Removes the queried item, or every item in the service when the query names no account.
    /// - Parameter query: The production deletion query.
    /// - Returns: Success or the absent-item status.
    func delete(matching query: [String: Any]) -> OSStatus {
        let (service, account) = scope(in: query)
        return state.withLock { state in
            let matches = state.items.keys.filter { $0.service == service && (account == nil || $0.account == account) }
            matches.forEach { state.items.removeValue(forKey: $0) }
            return matches.isEmpty ? errSecItemNotFound : errSecSuccess
        }
    }

    /// Extracts the item identity for queries that address one item.
    /// - Parameter query: The add or read attributes.
    /// - Returns: The scoped service and account.
    private func identity(in query: [String: Any]) -> Identity {
        let (service, account) = scope(in: query)
        return Identity(service: service, account: account!)
    }

    /// Extracts the service and optional account and records query scope and execution context.
    /// - Parameter query: The add, read, or delete attributes.
    /// - Returns: The scoped service, and the account when the query names one.
    private func scope(in query: [String: Any]) -> (service: String, account: String?) {
        state.withLock {
            $0.queriedOnlyLocalItems = $0.queriedOnlyLocalItems
                && query[kSecAttrSynchronizable as String] as? Bool == false
                && query[kSecUseDataProtectionKeychain as String] as? Bool == true
                && query[kSecClass as String] as? String == kSecClassGenericPassword as String
            $0.ranOffMainThread = $0.ranOffMainThread && !Thread.isMainThread
        }
        return (query[kSecAttrService as String] as! String, query[kSecAttrAccount as String] as? String)
    }
}

/// Observes invalidation without using the system's biometric prompt.
///
/// The only cross-thread test callback is immutable and Sendable. Inherited
/// context configuration remains owned by the production per-operation wrapper.
final class TestContext: LAContext, @unchecked Sendable {
    private let available: Bool
    private let onInvalidate: @Sendable () -> Void

    /// Creates a context with a thread-safe invalidation observer.
    /// - Parameters:
    ///   - available: Whether the test device has a passcode.
    ///   - onInvalidate: The callback invoked when authentication is invalidated.
    init(available: Bool = true, onInvalidate: @escaping @Sendable () -> Void = {}) {
        self.available = available
        self.onInvalidate = onInvalidate
        super.init()
    }

    /// Reports availability without consulting simulator authentication configuration.
    /// - Parameters:
    ///   - policy: The authentication policy requested by the production service.
    ///   - error: An optional error output, unused by this test context.
    /// - Returns: Whether the device has a passcode and the policy accepts biometrics or the passcode.
    override func canEvaluatePolicy(_ policy: LAPolicy, error: NSErrorPointer) -> Bool {
        available && policy == .deviceOwnerAuthentication
    }

    /// Records cancellation or completion before invalidating the context.
    override func invalidate() {
        onInvalidate()
        super.invalidate()
    }
}
