import Foundation
import LocalAuthentication
import Security
import Synchronization
import Testing
import Wallet
@testable import Vault

@Suite(.timeLimit(.minutes(1)))
struct KeychainStoreTests {
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

    @Test
    func `Saving an existing wallet preserves its original recovery material`() async throws {
        let keychain = KeychainStub()
        let store = KeychainStore(service: "test.recovery", keychain: keychain)
        let id = UUID()
        let original = try Fixtures.recovery()
        try await store.save(original, for: id)
        let replacement = Recovery(phrase: original.phrase, passphrase: "different")

        await #expect(throws: KeychainStoreError.duplicateRecovery) { try await store.save(replacement, for: id) }

        let recovered = try await store.recovery(for: id, reason: "Recover wallet")
        #expect(recovered.passphrase == original.passphrase)
    }

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
            case errSecAuthFailed: return error as? KeychainStoreError == .authenticationFailed
            case errSecItemNotFound: return error as? KeychainStoreError == .recoveryUnavailable
            default: return error as? KeychainStoreError == .interactionNotAllowed
            }
        }
        #expect(keychain.state.withLock(\.items) == original)
        keychain.state.withLock { $0.readStatus = errSecSuccess }
        let recovered = try await store.recovery(for: id, reason: "Try recovery again")
        #expect(recovered.passphrase == " TREZOR ")
    }

    @Test
    func `Reads in a shared authentication use one context that ends with the operation`() async throws {
        let contexts = Mutex<[TestContext]>([])
        let keychain = KeychainStub(contextFactory: {
            let context = TestContext()
            contexts.withLock { $0.append(context) }
            return context
        })
        let store: any RecoveryStoring = KeychainStore(service: "test.recovery", keychain: keychain)
        let ids = [UUID(), UUID()]
        for id in ids { try await store.save(Fixtures.recovery(), for: id) }

        let endedEarly = try await store.withSharedAuthentication(reason: "Approve transaction") { shared in
            _ = try await shared.recovery(for: ids[0], reason: "First read")
            let sharedContext = contexts.withLock(\.last)
            let endedEarly = try #require(sharedContext).waitForInvalidation(until: .now())
            _ = try await shared.recovery(for: ids[1], reason: "Second read")
            return endedEarly
        }

        let reads = keychain.state.withLock(\.readContexts)
        let made = contexts.withLock(\.last)
        let last = try #require(made)
        #expect(!endedEarly)
        #expect(reads == [ObjectIdentifier(last), ObjectIdentifier(last)])
        #expect(keychain.state.withLock(\.promptReasons) == ["Approve transaction", "Approve transaction"])
        #expect(last.waitForInvalidation(until: .now()))
    }

    @Test
    func `Cancelling recovery invalidates authentication without deleting the wallet`() async throws {
        let (started, signal) = AsyncStream<Void>.makeStream()
        let keychain = KeychainStub(beforeRead: { signal.yield(()) })
        let store = KeychainStore(service: "test.recovery", keychain: keychain)
        let id = UUID()
        try await store.save(Fixtures.recovery(), for: id)
        let original = keychain.state.withLock(\.items)
        keychain.state.withLock { $0.blocksReads = true }
        let read = Task { @concurrent in try await store.recovery(for: id, reason: "Recover wallet") }
        defer {
            read.cancel()
            signal.finish()
        }
        for await _ in started { break }

        read.cancel()

        await #expect(throws: CancellationError.self) { try await read.value }
        let readNotFreed = keychain.state.withLock(\.readNotFreed)
        #expect(!readNotFreed)
        #expect(keychain.state.withLock(\.items) == original)
    }

    @Test
    func `An authentication prompt that never appears frees the read as a retryable error`() async throws {
        let keychain = KeychainStub()
        let clock = ManualClock()
        let store = KeychainStore(service: "test.recovery", keychain: keychain, clock: clock)
        let id = UUID()
        try await store.save(Fixtures.recovery(), for: id)
        let original = keychain.state.withLock(\.items)
        keychain.state.withLock { $0.blocksReads = true }
        var waits = clock.waits.makeAsyncIterator()

        let read = Task { @concurrent in try await store.recovery(for: id, reason: "Recover wallet") }
        defer { read.cancel() }
        try await clock.advanceToNextWait(&waits)

        await #expect(throws: KeychainStoreError.interactionNotAllowed) { try await read.value }
        keychain.state.withLock { $0.blocksReads = false }
        let recovered = try await store.recovery(for: id, reason: "Try recovery again")

        #expect(recovered.passphrase == " TREZOR ")
        #expect(keychain.state.withLock(\.readCount) == 2)
        let readNotFreed = keychain.state.withLock(\.readNotFreed)
        #expect(!readNotFreed)
        #expect(keychain.state.withLock(\.items) == original)
    }

    @Test
    func `A read waiting behind another read gets its full time bound`() async throws {
        let (contexts, madeContext) = AsyncStream<Void>.makeStream()
        let keychain = KeychainStub(contextFactory: {
            madeContext.yield(())
            return TestContext()
        })
        let clock = ManualClock()
        let store = KeychainStore(service: "test.recovery", keychain: keychain, clock: clock)
        let id = UUID()
        try await store.save(Fixtures.recovery(), for: id)
        keychain.state.withLock { $0.blocksReads = true }
        var created = contexts.dropFirst(2).makeAsyncIterator()
        var waits = clock.waits.makeAsyncIterator()

        let first = Task { @concurrent in try await store.recovery(for: id, reason: "Recover wallet") }
        defer { first.cancel() }
        let firstDeadline = try #require(await clock.nextDeadline(&waits))
        let second = Task { @concurrent in
            try await store.recovery(for: id, reason: "Recover wallet in another window")
        }
        defer { second.cancel() }
        _ = await created.next()
        clock.advance(to: firstDeadline)
        let secondDeadline = try #require(await clock.nextDeadline(&waits))

        await #expect(throws: KeychainStoreError.interactionNotAllowed) { try await first.value }
        #expect(secondDeadline == firstDeadline.advanced(by: .seconds(30)))
        second.cancel()
        _ = await second.result
    }

    @Test
    func `Saving without a device passcode stores no recovery material`() async throws {
        let keychain = KeychainStub(contextFactory: { TestContext(available: false) })
        let store = KeychainStore(service: "test.recovery", keychain: keychain)
        let recovery = try Fixtures.recovery()

        await #expect(throws: KeychainStoreError.protectionUnavailable) {
            try await store.save(recovery, for: UUID())
        }
        let isEmpty = keychain.state.withLock(\.items.isEmpty)
        #expect(isEmpty)
    }

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

    @Test
    func `Deleting all recovery removes every wallet in its namespace only`() async throws {
        let keychain = KeychainStub()
        let store = KeychainStore(service: "test.recovery", keychain: keychain)
        let otherStore = KeychainStore(service: "test.other", keychain: keychain)
        let ids = [UUID(), UUID()]
        let otherID = UUID()
        let recovery = try Fixtures.recovery()
        for id in ids { try await store.save(recovery, for: id) }
        try await otherStore.save(recovery, for: otherID)

        try await store.deleteAllRecovery()
        try await store.deleteAllRecovery()

        for id in ids {
            await #expect(throws: KeychainStoreError.recoveryUnavailable) {
                try await store.recovery(for: id, reason: "Recover wallet")
            }
        }
        let other = try await otherStore.recovery(for: otherID, reason: "Recover other namespace")
        #expect(other.phrase.words == recovery.phrase.words)
        #expect(keychain.state.withLock(\.items.count) == 1)
        let queriedOnlyLocalItems = keychain.state.withLock(\.queriedOnlyLocalItems)
        #expect(queriedOnlyLocalItems)
    }

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

        await #expect(throws: KeychainStoreError.recoveryUnavailable) {
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

        await #expect(throws: KeychainStoreError.invalidRecovery) {
            try await store.recovery(for: id, reason: "Recover wallet")
        }
        #expect(keychain.state.withLock(\.items) == original)
    }
}
