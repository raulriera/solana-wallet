import Dispatch
public import Foundation
import LocalAuthentication
import Security

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
    private let queue = DispatchQueue(label: "Vault.Keychain", qos: .userInitiated)

    /// Creates device-only storage in the app's Keychain access group.
    ///
    /// - Parameter service: A stable, app-specific namespace, such as `com.example.wallet.recovery`.
    public init(service: String) {
        self.service = service
        keychain = SystemKeychain()
    }

    /// Creates storage with injected Keychain operations for focused verification.
    ///
    /// - Parameters:
    ///   - service: The stable storage namespace.
    ///   - keychain: The implementation of Security operations.
    init(service: String, keychain: any KeychainAccessing) {
        self.service = service
        self.keychain = keychain
    }

    /// Saves recovery material without overwriting an existing wallet.
    ///
    /// Requires a device passcode; biometrics are optional. Cancellation doesn't
    /// roll back an add that has already reached the Keychain.
    ///
    /// - Parameters:
    ///   - recovery: The shared phrase and original BIP-39 passphrase.
    ///   - walletID: The caller's local wallet identifier.
    /// - Throws: ``KeychainStoreError`` if the item can't be protected or already exists,
    ///   or `CancellationError` if canceled.
    public func save(_ recovery: Recovery, for walletID: UUID) async throws {
        try await perform { context in
            guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else {
                throw KeychainStoreError.protectionUnavailable
            }
            guard let access = SecAccessControlCreateWithFlags(
                nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, .userPresence, nil
            ) else { throw KeychainStoreError.protectionUnavailable }
            var payload = try StoredRecovery.encode(recovery)
            var attributes = identity(for: walletID)
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
    ///   - walletID: The local identifier used when saving the wallet.
    ///   - reason: A localized, secret-free explanation shown during authentication.
    /// - Returns: The validated recovery material.
    /// - Throws: ``KeychainStoreError`` if access fails, or `CancellationError` if canceled.
    public func recovery(for walletID: UUID, reason: String) async throws -> Recovery {
        try await perform(reason: reason) { context in
            var query = identity(for: walletID)
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
    /// - Parameter walletID: The local identifier to remove.
    /// - Throws: ``KeychainStoreError`` if deletion fails, or `CancellationError` if canceled.
    public func deleteRecovery(for walletID: UUID) async throws {
        try await perform { _ in
            let status = keychain.delete(matching: identity(for: walletID))
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
    /// - Parameter walletID: The local identifier used as the Keychain account.
    /// - Returns: The common attributes for add, read, and delete queries.
    private func identity(for walletID: UUID) -> [String: Any] {
        namespace.merging([kSecAttrAccount as String: walletID.uuidString]) { $1 }
    }

    /// Runs a blocking Keychain operation outside Swift's cooperative executor.
    ///
    /// - Parameters:
    ///   - reason: The localized authentication explanation, when reading an item.
    ///   - operation: Work whose queries and context stay on the background queue.
    /// - Returns: The operation's result after checking cancellation.
    /// - Throws: The operation's error, or `CancellationError` if canceled.
    private func perform<Value: Sendable>(
        reason: String = "",
        _ operation: @escaping Operation<Value>
    ) async throws -> Value {
        try Task.checkCancellation()
        let authentication = AuthenticationContext(context: keychain.makeContext(), reason: reason)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.async {
                    defer { authentication.finish() }
                    let result = Result {
                        try authentication.checkCancellation()
                        return try operation(authentication.context)
                    }
                    do {
                        try authentication.checkCancellation()
                        continuation.resume(with: result)
                    } catch { continuation.resume(throwing: error) }
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
        case errSecDuplicateItem: throw KeychainStoreError.duplicateWallet
        case errSecItemNotFound: throw KeychainStoreError.recoveryUnavailable
        case errSecUserCanceled: throw CancellationError()
        case errSecAuthFailed: throw KeychainStoreError.authenticationFailed
        case errSecInteractionNotAllowed: throw KeychainStoreError.interactionNotAllowed
        default: throw KeychainStoreError.keychain(status: status)
        }
    }
}
