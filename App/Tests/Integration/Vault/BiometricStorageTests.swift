import Foundation
import LocalAuthentication
import Testing
import Vault
import Wallet

/// Opt-in checks against the real Keychain on an isolated, unfunded simulator.
@Suite(.timeLimit(.minutes(1)))
struct BiometricStorageTests {
    /// Verifies the device passcode still protects a real Keychain round trip without enrolled biometrics.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["BIOMETRIC_TEST_STATE"] == "unenrolled"))
    func `Unenrolled Touch ID still permits saving and reading wallet recovery`() async throws {
        let context = LAContext()
        var error: NSError?
        try #require(!context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error))
        try #require(error?.code == LAError.biometryNotEnrolled.rawValue)
        try #require(context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil))
        try await verifyRoundTrip()
    }

    /// Verifies enrolled Touch ID permits a real protected Keychain round trip.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["BIOMETRIC_TEST_STATE"] == "enrolled"))
    func `Enrolled Touch ID permits saving and reading wallet recovery`() async throws {
        let context = LAContext()
        try #require(context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil))
        try #require(context.biometryType == .touchID)
        try await verifyRoundTrip()
    }

    /// Saves, reads, and deletes a public fixture in the real Keychain.
    /// - Throws: A storage error, after removing any saved test item.
    private func verifyRoundTrip() async throws {
        let store = KeychainStore(service: "widgetsTests.biometric-probe")
        let id = UUID()
        let original = try recovery()
        do {
            try await store.save(original, for: id)
            let restored = try await store.recovery(for: id, reason: "Read public biometric test fixture")
            #expect(restored.phrase.words == original.phrase.words)
            #expect(restored.passphrase == original.passphrase)
        } catch {
            try? await store.deleteRecovery(for: id)
            throw error
        }
        try await store.deleteRecovery(for: id)
    }

    /// Creates a public BIP-39 fixture that must never receive funds.
    ///
    /// - Returns: Public recovery material for a disposable Keychain item.
    /// - Throws: A phrase validation error if the fixture is malformed.
    private func recovery() throws -> Recovery {
        try Recovery(
            phrase: RecoveryPhrase(Array(repeating: "abandon", count: 11).joined(separator: " ") + " about"),
            passphrase: "biometric-test"
        )
    }
}
