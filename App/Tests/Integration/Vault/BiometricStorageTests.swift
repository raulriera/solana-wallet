import Foundation
import LocalAuthentication
import Testing
import Vault
import Wallet

@Suite(.timeLimit(.minutes(1)))
struct BiometricStorageTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["BIOMETRIC_TEST_STATE"] == "unenrolled"))
    func `Unenrolled Touch ID still permits saving and reading wallet recovery`() async throws {
        let context = LAContext()
        var error: NSError?
        try #require(!context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error))
        try #require(error?.code == LAError.biometryNotEnrolled.rawValue)
        try #require(context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil))
        try await verifyRoundTrip()
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["BIOMETRIC_TEST_STATE"] == "enrolled"))
    func `Enrolled Touch ID permits saving and reading wallet recovery`() async throws {
        let context = LAContext()
        try #require(context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil))
        try #require(context.biometryType == .touchID)
        try await verifyRoundTrip()
    }

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

    private func recovery() throws -> Recovery {
        try Recovery(
            phrase: RecoveryPhrase(ThrowawayWallet.words),
            passphrase: "biometric-test"
        )
    }
}
