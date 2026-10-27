import Dispatch
public import Foundation
import LocalAuthentication
import Security
import Synchronization

/// Device-only recovery storage that opens with biometrics or the device passcode.
///
/// Each read uses a fresh authentication context. No item synchronizes to iCloud
/// or migrates to another device. Authentication failures never delete or
/// replace stored recovery material.
public struct KeychainStore: RecoveryStoring {
    /// Blocking work that uses an authentication context only on the Keychain queue.
    private typealias Operation<Value: Sendable> = @Sendable (LAContext) throws -> Value

    private let service: String
    private let keychain: any KeychainAccessing
    private let authenticationTimeout: Duration
    private let queue = DispatchQueue(label: "Vault.Keychain", qos: .userInitiated)

    /// The longest a recovery read waits, once it starts, before it ends authentication and reports
    /// ``KeychainStoreError/interactionNotAllowed``.
    ///
    /// System UI, such as a notification banner, can take over presentation just as the biometric prompt would
    /// appear, so the prompt never shows and the Keychain read would otherwise wait with no end. Operations run one
    /// at a time, and time spent waiting behind an earlier one doesn't count. The bound does count time spent
    /// answering a prompt that shows, so a prompt still open at the bound closes. The error is retryable, so a later
    /// attempt, once presentation is free, succeeds.
    static let defaultAuthenticationTimeout = Duration.seconds(30)

    /// Creates device-only storage in the app's Keychain access group.
    ///
    /// - Parameter service: A stable, app-specific namespace, such as `com.example.wallet.recovery`.
    public init(service: String) {
        self.init(service: service, keychain: SystemKeychain())
    }

    /// Creates storage with injected Keychain operations for focused verification.
    ///
    /// - Parameters:
    ///   - service: The stable storage namespace.
    ///   - keychain: The implementation of Security operations.
    ///   - authenticationTimeout: How long a read waits, once it starts, before it reports
    ///     ``KeychainStoreError/interactionNotAllowed``.
    init(service: String, keychain: any KeychainAccessing,
         authenticationTimeout: Duration = KeychainStore.defaultAuthenticationTimeout) {
        self.service = service
        self.keychain = keychain
        self.authenticationTimeout = authenticationTimeout
    }

    /// Saves recovery material without overwriting an existing wallet.
    ///
    /// Requires a device passcode; biometrics are optional. Cancellation doesn't
    /// roll back an add that has already reached the Keychain.
    ///
    /// - Parameters:
    ///   - recovery: The shared phrase and original BIP-39 passphrase.
    ///   - recoveryID: The caller's local recovery identifier.
    /// - Throws: ``KeychainStoreError`` if the item can't be protected or already exists,
    ///   or `CancellationError` if canceled.
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
                // Best effort: release the dictionary's reference first so the zeroing reaches the shared buffer.
                attributes[kSecValueData as String] = nil
                payload.resetBytes(in: 0..<payload.count)
            }
            try Self.check(keychain.add(attributes))
        }
    }

    /// Retrieves recovery material after biometric or device passcode authentication.
    ///
    /// The calling app must supply `NSFaceIDUsageDescription`. Biometric enrollment
    /// changes don't affect access. A missing item requires the user's backup.
    ///
    /// - Parameters:
    ///   - recoveryID: The local identifier used when saving the recovery.
    ///   - reason: A localized, secret-free explanation shown during authentication.
    /// - Returns: The validated recovery material.
    /// - Throws: ``KeychainStoreError`` if access fails, including ``KeychainStoreError/interactionNotAllowed`` when
    ///   authentication doesn't finish within the time bound, or `CancellationError` if canceled.
    public func recovery(for recoveryID: UUID, reason: String) async throws -> Recovery {
        try await perform(reason: reason, timeout: authenticationTimeout) { context in
            var query = identity(for: recoveryID)
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            query[kSecReturnData as String] = true
            query[kSecUseAuthenticationContext as String] = context
            var result = keychain.copy(matching: query)
            try Self.check(result.status)
            // Taking the value leaves this copy as the only owner, so zeroing reaches the real buffer.
            guard var data = result.data.take() else { throw KeychainStoreError.invalidRecovery }
            // Best effort: the decoded phrase lives on as Strings, but the raw payload is zeroed.
            defer { data.resetBytes(in: 0..<data.count) }
            return try StoredRecovery.decode(data)
        }
    }

    /// Deletes one wallet's recovery material without reading or unlocking it.
    ///
    /// Call only after the user explicitly chooses to remove the wallet. This
    /// also permits removing inaccessible items. Cancellation doesn't roll back
    /// a deletion already performed by the Keychain.
    ///
    /// - Parameter recoveryID: The local identifier to remove.
    /// - Throws: ``KeychainStoreError`` if deletion fails, or `CancellationError` if canceled.
    public func deleteRecovery(for recoveryID: UUID) async throws {
        try await perform { _ in
            let status = keychain.delete(matching: identity(for: recoveryID))
            if status != errSecItemNotFound { try Self.check(status) }
        }
    }

    /// Deletes every wallet's recovery material in this namespace without reading or unlocking it.
    ///
    /// Call only after the user explicitly chooses to reset the app. This also removes
    /// items that no saved wallet references. Cancellation doesn't roll back a deletion
    /// already performed by the Keychain.
    ///
    /// - Throws: ``KeychainStoreError`` if deletion fails, or `CancellationError` if canceled.
    public func deleteAllRecovery() async throws {
        try await perform { _ in
            let status = keychain.delete(matching: namespace)
            if status != errSecItemNotFound { try Self.check(status) }
        }
    }

    /// Matches every non-synchronizing item in this app's namespace.
    private var namespace: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrSynchronizable as String: false,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }

    /// Identifies one non-synchronizing item within this app's namespace.
    /// - Parameter recoveryID: The local identifier used as the Keychain account.
    /// - Returns: The common attributes for add, read, and delete queries.
    private func identity(for recoveryID: UUID) -> [String: Any] {
        namespace.merging([kSecAttrAccount as String: recoveryID.uuidString]) { $1 }
    }

    /// Runs a blocking Keychain operation outside Swift's cooperative executor, optionally within a time bound.
    ///
    /// With a `timeout`, the caller resumes at the bound even if the blocking Keychain call never returns, and
    /// invalidating the context dismisses any pending prompt.
    /// - Parameters:
    ///   - reason: The localized authentication explanation, when reading an item.
    ///   - timeout: How long to wait once the operation starts on the Keychain queue before reporting
    ///     ``KeychainStoreError/interactionNotAllowed``, or `nil` to wait without a bound, as for operations that
    ///     never present a prompt.
    ///   - operation: Work whose queries and context stay on the background queue.
    /// - Returns: The operation's result after checking cancellation.
    /// - Throws: The operation's error, ``KeychainStoreError/interactionNotAllowed`` at the time bound, or
    ///   `CancellationError` if canceled.
    private func perform<Value: Sendable>(
        reason: String = "",
        timeout: Duration? = nil,
        _ operation: @escaping Operation<Value>
    ) async throws -> Value {
        try Task.checkCancellation()
        let authentication = AuthenticationContext(context: keychain.makeContext(), reason: reason)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                // The operation and the time bound race to resume the caller; only the first one does.
                let pending = Mutex<CheckedContinuation<Value, any Error>?>(continuation)
                let resume: @Sendable (Result<Value, any Error>) -> Void = { result in
                    pending.withLock { $0.take() }?.resume(with: result)
                }
                queue.async {
                    // The bound starts once the operation runs, so time spent waiting behind another one doesn't count.
                    let timer = timeout.map { timeout in
                        Task { @concurrent in
                            try await Task.sleep(for: timeout)
                            authentication.timeOut()
                            // The outcome is final now, so this reports the timeout, or a cancellation that came first.
                            do { try authentication.checkRunning() } catch { resume(.failure(error)) }
                        }
                    }
                    defer {
                        authentication.finish()
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

    /// Converts a Security status into a secret-free storage error.
    /// - Parameter status: The status returned by the Keychain operation.
    /// - Throws: A matching ``KeychainStoreError`` or `CancellationError` for user cancellation.
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
