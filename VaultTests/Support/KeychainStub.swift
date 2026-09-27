import Foundation
import LocalAuthentication
import Security
import Synchronization
@testable import Vault

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
        var permitsFallback = false
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
            nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, .biometryCurrentSet, nil
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
            $0.permitsFallback = $0.permitsFallback || context.localizedFallbackTitle != ""
                || context.touchIDAuthenticationAllowableReuseDuration != 0
            $0.readCount += 1
        }
        beforeRead()
        return state.withLock {
            guard $0.readStatus == errSecSuccess else { return ($0.readStatus, nil) }
            guard let data = $0.dataOverride ?? $0.items[identity] else { return (errSecItemNotFound, nil) }
            return (errSecSuccess, data)
        }
    }

    /// Removes only the queried item.
    /// - Parameter query: The production deletion query.
    /// - Returns: Success or the absent-item status.
    func delete(matching query: [String: Any]) -> OSStatus {
        let identity = identity(in: query)
        return state.withLock { $0.items.removeValue(forKey: identity) == nil ? errSecItemNotFound : errSecSuccess }
    }

    /// Extracts the item identity and records query scope and execution context.
    /// - Parameter query: The add, read, or delete attributes.
    /// - Returns: The scoped service and account.
    private func identity(in query: [String: Any]) -> Identity {
        state.withLock {
            $0.queriedOnlyLocalItems = $0.queriedOnlyLocalItems
                && query[kSecAttrSynchronizable as String] as? Bool == false
                && query[kSecUseDataProtectionKeychain as String] as? Bool == true
                && query[kSecClass as String] as? String == kSecClassGenericPassword as String
            $0.ranOffMainThread = $0.ranOffMainThread && !Thread.isMainThread
        }
        return Identity(service: query[kSecAttrService as String] as! String, account: query[kSecAttrAccount as String] as! String)
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
    ///   - available: Whether the test permits biometric authentication.
    ///   - onInvalidate: The callback invoked when authentication is invalidated.
    init(available: Bool = true, onInvalidate: @escaping @Sendable () -> Void = {}) {
        self.available = available
        self.onInvalidate = onInvalidate
        super.init()
    }

    /// Reports availability without consulting simulator biometric configuration.
    /// - Parameters:
    ///   - policy: The authentication policy requested by the production service.
    ///   - error: An optional error output, unused by this test context.
    /// - Returns: Whether biometrics are available and the policy excludes passcode fallback.
    override func canEvaluatePolicy(_ policy: LAPolicy, error: NSErrorPointer) -> Bool {
        available && policy == .deviceOwnerAuthenticationWithBiometrics
    }

    /// Records cancellation or completion before invalidating the context.
    override func invalidate() {
        onInvalidate()
        super.invalidate()
    }
}
