import Dispatch
import Foundation
import LocalAuthentication
import Security
import Synchronization
@testable import Vault

// swift-format-ignore: NeverForceUnwrap
final class KeychainStub: KeychainAccessing {
    struct Identity: Hashable {
        let service: String
        let account: String
    }

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
        var blocksReads = false
        var readNotFreed = false
    }

    let state = Mutex(State())
    private let contextFactory: @Sendable () -> LAContext
    private let beforeRead: @Sendable () -> Void

    init(
        contextFactory: @escaping @Sendable () -> LAContext = { TestContext() },
        beforeRead: @escaping @Sendable () -> Void = {}
    ) {
        self.contextFactory = contextFactory
        self.beforeRead = beforeRead
    }

    func makeContext() -> LAContext { contextFactory() }

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

    func copy(matching query: [String: Any]) -> (status: OSStatus, data: Data?) {
        let identity = identity(in: query)
        let context = query[kSecUseAuthenticationContext as String] as! LAContext
        let blocksRead = state.withLock {
            $0.promptReasons.append(context.localizedReason)
            $0.hidesPasscode = $0.hidesPasscode || context.localizedFallbackTitle == ""
            $0.reusesUnlock = $0.reusesUnlock || context.touchIDAuthenticationAllowableReuseDuration != 0
            $0.readCount += 1
            return $0.blocksReads
        }
        beforeRead()
        if blocksRead, (context as? TestContext)?.waitForInvalidation(until: .now() + 5) != true {
            state.withLock { $0.readNotFreed = true }
        }
        return state.withLock {
            guard $0.readStatus == errSecSuccess else { return ($0.readStatus, nil) }
            guard let data = $0.dataOverride ?? $0.items[identity] else { return (errSecItemNotFound, nil) }
            return (errSecSuccess, data)
        }
    }

    func delete(matching query: [String: Any]) -> OSStatus {
        let (service, account) = scope(in: query)
        return state.withLock { state in
            let matches = state.items.keys.filter { $0.service == service && (account == nil || $0.account == account) }
            matches.forEach { state.items.removeValue(forKey: $0) }
            return matches.isEmpty ? errSecItemNotFound : errSecSuccess
        }
    }

    private func identity(in query: [String: Any]) -> Identity {
        let (service, account) = scope(in: query)
        return Identity(service: service, account: account!)
    }

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

final class TestContext: LAContext, @unchecked Sendable {
    private let available: Bool
    private let invalidation = DispatchSemaphore(value: 0)

    init(available: Bool = true) {
        self.available = available
        super.init()
    }

    func waitForInvalidation(until deadline: DispatchTime) -> Bool {
        invalidation.wait(timeout: deadline) == .success
    }

    override func canEvaluatePolicy(_ policy: LAPolicy, error: NSErrorPointer) -> Bool {
        available && policy == .deviceOwnerAuthentication
    }

    override func invalidate() {
        invalidation.signal()
        super.invalidate()
    }
}
