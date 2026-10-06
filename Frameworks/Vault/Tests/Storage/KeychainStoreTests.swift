import Dispatch
import Foundation
import LocalAuthentication
import Security
import Synchronization
import Testing
import Wallet
@testable import Vault

/// Verifies storage behavior with isolated Keychain data and no biometric prompts.
@Suite(.timeLimit(.minutes(1)))
struct KeychainStoreTests {
    /// Verifies complete recovery and the device-only biometric-or-passcode policy in the outgoing query.
    @Test
    func `Saved recovery preserves the phrase and passphrase`() async throws {
        let keychain = KeychainStub()
        let store: any RecoveryStoring = KeychainStore(service: "test.recovery", keychain: keychain)
        let id = UUID()
        let original = try Fixtures.recovery()
        try await store.save(original, for: id)

        let recovered = try await store.recovery(for: id, reason: "Reveal recovery phrase")

        #expect(recovered.phrase.words == original.phrase.words)
        #expect(recovered.passphrase == " TREZOR ")
        let payload = try #require(keychain.state.withLock(\.items).values.first)
        let stored = try #require(JSONSerialization.jsonObject(with: payload) as? [String: Any])
        #expect(stored["path"] == nil)
        let hasRequiredProtection = keychain.state.withLock(\.hasRequiredProtection)
        let queriedOnlyLocalItems = keychain.state.withLock(\.queriedOnlyLocalItems)
        let ranOffMainThread = keychain.state.withLock(\.ranOffMainThread)
        let hidesPasscode = keychain.state.withLock(\.hidesPasscode)
        let reusesUnlock = keychain.state.withLock(\.reusesUnlock)
        #expect(hasRequiredProtection)
        #expect(queriedOnlyLocalItems)
        #expect(ranOffMainThread)
        #expect(keychain.state.withLock(\.promptReasons) == ["Reveal recovery phrase"])
        #expect(!hidesPasscode)
        #expect(!reusesUnlock)
    }

    /// Verifies that a duplicate save never replaces an existing wallet's secrets.
    @Test
    func `Saving an existing wallet preserves its original recovery material`() async throws {
        let keychain = KeychainStub()
        let store = KeychainStore(service: "test.recovery", keychain: keychain)
        let id = UUID()
        let original = try Fixtures.recovery()
        try await store.save(original, for: id)
        let replacement = Recovery(phrase: original.phrase, passphrase: "different")

        await #expect(throws: KeychainStore.Failure.duplicateWallet) { try await store.save(replacement, for: id) }

        let recovered = try await store.recovery(for: id, reason: "Recover wallet")
        #expect(recovered.passphrase == original.passphrase)
    }

    /// Verifies distinct error mapping and retention after unsuccessful authentication or missing access.
    /// - Parameter status: The Security failure returned by the read operation.
    @Test(arguments: [
        errSecAuthFailed, errSecUserCanceled, errSecItemNotFound, errSecInteractionNotAllowed,
    ])
    func `Failed recovery reads preserve stored material`(status: OSStatus) async throws {
        let keychain = KeychainStub()
        let store = KeychainStore(service: "test.recovery", keychain: keychain)
        let id = UUID()
        try await store.save(Fixtures.recovery(), for: id)
        let original = keychain.state.withLock(\.items)
        keychain.state.withLock { $0.readStatus = status }

        await #expect {
            try await store.recovery(for: id, reason: "Recover wallet")
        } throws: { error in
            switch status {
            case errSecUserCanceled: return error is CancellationError
            case errSecAuthFailed: return error as? KeychainStore.Failure == .authenticationFailed
            case errSecItemNotFound: return error as? KeychainStore.Failure == .recoveryUnavailable
            default: return error as? KeychainStore.Failure == .interactionNotAllowed
            }
        }
        #expect(keychain.state.withLock(\.items) == original)
        keychain.state.withLock { $0.readStatus = errSecSuccess }
        let recovered = try await store.recovery(for: id, reason: "Try recovery again")
        #expect(recovered.passphrase == " TREZOR ")
    }

    /// Verifies that canceling an in-flight read invalidates its context and preserves storage.
    @Test
    func `Cancelling recovery invalidates authentication without deleting the wallet`() async throws {
        let (started, signal) = AsyncStream<Void>.makeStream()
        let blocked = Mutex(false)
        let timedOut = Mutex(false)
        let release = DispatchSemaphore(value: 0)
        let keychain = KeychainStub(
            contextFactory: {
                TestContext { if blocked.withLock(\.self) { release.signal() } }
            },
            beforeRead: {
                blocked.withLock { $0 = true }
                signal.yield(())
                // Simulate the blocking Security call only on the dedicated background queue.
                if release.wait(timeout: .now() + 5) == .timedOut { timedOut.withLock { $0 = true } }
            }
        )
        let store = KeychainStore(service: "test.recovery", keychain: keychain)
        let id = UUID()
        try await store.save(Fixtures.recovery(), for: id)
        let original = keychain.state.withLock(\.items)
        let read = Task { @concurrent in try await store.recovery(for: id, reason: "Recover wallet") }
        defer { read.cancel(); release.signal(); signal.finish() }
        for await _ in started { break }

        read.cancel()

        await #expect(throws: CancellationError.self) { try await read.value }
        #expect(!timedOut.withLock { $0 })
        #expect(keychain.state.withLock(\.items) == original)
    }

    /// Verifies that a device without a passcode never gets weaker or unusable storage.
    @Test
    func `Saving without a device passcode stores no recovery material`() async throws {
        let keychain = KeychainStub(contextFactory: { TestContext(available: false) })
        let store = KeychainStore(service: "test.recovery", keychain: keychain)
        let recovery = try Fixtures.recovery()

        await #expect(throws: KeychainStore.Failure.protectionUnavailable) {
            try await store.save(recovery, for: UUID())
        }
        let isEmpty = keychain.state.withLock(\.items.isEmpty)
        #expect(isEmpty)
    }

    /// Verifies that canceled callers don't reach Security or open authentication prompts.
    @Test
    func `Already cancelled recovery never queries the Keychain`() async {
        let keychain = KeychainStub()
        let store = KeychainStore(service: "test.recovery", keychain: keychain)
        let (gate, continuation) = AsyncStream<Void>.makeStream()
        let task = Task { @concurrent in
            for await _ in gate {}
            return try await store.recovery(for: UUID(), reason: "Recover wallet")
        }
        task.cancel()
        continuation.finish()

        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(keychain.state.withLock(\.readCount) == 0)
    }

    /// Verifies exact deletion scope across wallet identifiers and service namespaces.
    @Test
    func `Deleting recovery preserves other wallets and namespaces`() async throws {
        let keychain = KeychainStub()
        let store = KeychainStore(service: "test.recovery", keychain: keychain)
        let otherStore = KeychainStore(service: "test.other", keychain: keychain)
        let id = UUID()
        let otherID = UUID()
        let recovery = try Fixtures.recovery()
        try await store.save(recovery, for: id)
        try await store.save(recovery, for: otherID)
        try await otherStore.save(recovery, for: id)

        try await store.deleteRecovery(for: id)
        try await store.deleteRecovery(for: id)

        await #expect(throws: KeychainStore.Failure.recoveryUnavailable) {
            try await store.recovery(for: id, reason: "Recover wallet")
        }
        let first = try await store.recovery(for: otherID, reason: "Recover other wallet")
        let second = try await otherStore.recovery(for: id, reason: "Recover other namespace")
        #expect(first.phrase.words == recovery.phrase.words)
        #expect(second.phrase.words == recovery.phrase.words)
        #expect(keychain.state.withLock(\.items.count) == 2)
        let queriedOnlyLocalItems = keychain.state.withLock(\.queriedOnlyLocalItems)
        #expect(queriedOnlyLocalItems)
    }

    /// Verifies that malformed or unsupported stored values fail without exposing or deleting them.
    /// - Parameter invalid: A public malformed fixture returned by the test Keychain.
    @Test(arguments: [
        "not-json",
        "{\"version\":2,\"phrase\":\"secret-marker\",\"passphrase\":\"secret-marker\"}",
        "{\"version\":1,\"phrase\":\"secret-marker\",\"passphrase\":\"secret-marker\"}",
    ])
    func `Invalid stored recovery is rejected without being erased`(invalid: String) async throws {
        let keychain = KeychainStub()
        let store = KeychainStore(service: "test.recovery", keychain: keychain)
        let id = UUID()
        try await store.save(Fixtures.recovery(), for: id)
        let original = keychain.state.withLock(\.items)
        keychain.state.withLock { $0.dataOverride = Data(invalid.utf8) }

        await #expect(throws: KeychainStore.Failure.invalidRecovery) {
            try await store.recovery(for: id, reason: "Recover wallet")
        }
        #expect(keychain.state.withLock(\.items) == original)
    }
}
