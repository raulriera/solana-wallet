import Dispatch
public import Foundation
import LocalAuthentication
import Security
import Synchronization

/// Device-only recovery storage that opens with biometrics or the device passcode.
public struct KeychainStore: RecoveryStoring {
    /// Blocking Keychain work that receives an authentication context.
    private typealias Operation<Value: Sendable> = @Sendable (LAContext) throws -> Value

    private let service: String
    private let keychain: any KeychainAccessing
    private let clock: any Clock<Duration>
    /// The authentication that this store's operations share, or `nil` if each operation has its own.
    private let authentication: AuthenticationContext?
    private let queue = DispatchQueue(label: "Vault.Keychain", qos: .userInitiated)

    /// The longest a recovery read waits for authentication once it starts.
    private static let authenticationTimeout = Duration.seconds(30)

    /// Creates device-only storage in the app's Keychain access group.
    ///
    /// - Parameter service: The app-specific Keychain service name.
    public init(service: String) {
        self.init(service: service, keychain: SystemKeychain())
    }

    /// Creates storage with injected Keychain operations.
    ///
    /// - Parameters:
    ///   - service: The app-specific Keychain service name.
    ///   - keychain: The Keychain operations.
    ///   - clock: The clock that times authentication.
    ///   - authentication: The authentication that the store's operations share, or `nil` if each has its own.
    init(service: String, keychain: any KeychainAccessing, clock: any Clock<Duration> = ContinuousClock(),
         authentication: AuthenticationContext? = nil) {
        self.service = service
        self.keychain = keychain
        self.clock = clock
        self.authentication = authentication
    }

    public func save(_ recovery: Recovery, for recoveryID: UUID) async throws {
        try await perform { context in
            guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else {
                throw KeychainStoreError.protectionUnavailable
            }
            guard let access = SecAccessControlCreateWithFlags(
                nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, .userPresence, nil
            ) else { throw KeychainStoreError.protectionUnavailable }
            var payload = try StoredRecovery.encode(recovery)
            var attributes = identity(for: recoveryID)
            attributes[kSecAttrAccessControl as String] = access
            attributes[kSecValueData as String] = payload
            defer {
                attributes[kSecValueData as String] = nil
                payload.resetBytes(in: 0..<payload.count)
            }
            try Self.check(keychain.add(attributes))
        }
    }

    public func recovery(for recoveryID: UUID, reason: String) async throws -> Recovery {
        try await perform(reason: reason, timeout: Self.authenticationTimeout) { context in
            var query = identity(for: recoveryID)
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            query[kSecReturnData as String] = true
            query[kSecUseAuthenticationContext as String] = context
            var result = keychain.copy(matching: query)
            try Self.check(result.status)
            guard var data = result.data.take() else { throw KeychainStoreError.invalidRecovery }
            defer { data.resetBytes(in: 0..<data.count) }
            return try StoredRecovery.decode(data)
        }
    }

    public func withSharedAuthentication<Value: Sendable>(
        reason: String, _ operation: @Sendable (any RecoveryStoring) async throws -> Value
    ) async throws -> Value {
        if authentication != nil { return try await operation(self) }
        let authentication = AuthenticationContext(context: keychain.makeContext(), reason: reason)
        defer { authentication.finish() }
        return try await operation(
            KeychainStore(service: service, keychain: keychain, clock: clock, authentication: authentication)
        )
    }

    public func deleteRecovery(for recoveryID: UUID) async throws {
        try await perform { _ in
            let status = keychain.delete(matching: identity(for: recoveryID))
            if status != errSecItemNotFound { try Self.check(status) }
        }
    }

    public func deleteAllRecovery() async throws {
        try await perform { _ in
            let status = keychain.delete(matching: namespace)
            if status != errSecItemNotFound { try Self.check(status) }
        }
    }

    /// The query attributes that match every item in the service.
    private var namespace: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrSynchronizable as String: false,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }

    /// Returns the query attributes that identify one recovery item.
    ///
    /// - Parameter recoveryID: The recovery material's identifier.
    /// - Returns: The item's query attributes.
    private func identity(for recoveryID: UUID) -> [String: Any] {
        namespace.merging([kSecAttrAccount as String: recoveryID.uuidString]) { $1 }
    }

    /// Runs a blocking Keychain operation on the Keychain queue, optionally within a time limit, with the shared
    /// authentication or one of its own that ends with the operation.
    ///
    /// - Parameters:
    ///   - reason: The localized reason to show during an authentication of its own.
    ///   - timeout: The longest to wait once the operation starts, or `nil` for no limit.
    ///   - operation: The blocking Keychain work.
    /// - Returns: The operation's result.
    /// - Throws: The operation's error, ``KeychainStoreError/interactionNotAllowed`` on timeout, or
    ///   `CancellationError`.
    private func perform<Value: Sendable>(
        reason: String = "",
        timeout: Duration? = nil,
        _ operation: @escaping Operation<Value>
    ) async throws -> Value {
        try Task.checkCancellation()
        let shared = self.authentication
        let authentication = shared ?? AuthenticationContext(context: keychain.makeContext(), reason: reason)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let pending = Mutex<CheckedContinuation<Value, any Error>?>(continuation)
                let resume: @Sendable (Result<Value, any Error>) -> Void = { result in
                    pending.withLock { $0.take() }?.resume(with: result)
                }
                queue.async {
                    let timer = timeout.map { timeout in
                        Task { @concurrent in
                            try await clock.sleep(for: timeout)
                            authentication.timeOut()
                            do { try authentication.checkRunning() } catch { resume(.failure(error)) }
                        }
                    }
                    defer {
                        if shared == nil { authentication.finish() }
                        timer?.cancel()
                    }
                    let result = Result {
                        try authentication.checkRunning()
                        return try operation(authentication.context)
                    }
                    do {
                        try authentication.checkRunning()
                        resume(result)
                    } catch { resume(.failure(error)) }
                }
            }
        } onCancel: { authentication.cancel() }
    }

    /// Throws the error that matches a Security status other than success.
    ///
    /// - Parameter status: The status returned by the Keychain operation.
    /// - Throws: A matching ``KeychainStoreError``, or `CancellationError` if the user cancelled.
    private static func check(_ status: OSStatus) throws {
        switch status {
        case errSecSuccess: return
        case errSecDuplicateItem: throw KeychainStoreError.duplicateRecovery
        case errSecItemNotFound: throw KeychainStoreError.recoveryUnavailable
        case errSecUserCanceled: throw CancellationError()
        case errSecAuthFailed: throw KeychainStoreError.authenticationFailed
        case errSecInteractionNotAllowed: throw KeychainStoreError.interactionNotAllowed
        default: throw KeychainStoreError.keychain(status: status)
        }
    }
}
