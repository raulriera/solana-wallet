import Foundation
import Testing
import Vault
import Wallet
@testable import widgets

@Suite(.timeLimit(.minutes(1)))
struct RecoveryRevealTests {
    @Test
    func `Showing recovery returns the words, passphrase, and the wallet's own path`() async throws {
        let account = try Account.fixture(index: 3)
        let recovery = try ThrowawayWallet.recovery(passphrase: " TREZOR ")
        let store = SecurityRecoveryStore(records: [account.recoveryID: recovery])

        let display = try await RecoveryReveal(store: store).display(for: account)

        guard case .backup(let backup) = display else {
            Issue.record("Expected the wallet's backup")
            return
        }
        #expect(backup.phrase.words == recovery.phrase.words)
        #expect(backup.passphrase == " TREZOR ")
        #expect(backup.path == account.path)
        #expect(await store.reads == [account.recoveryID])
    }

    @Test
    func `A missing recovery shows that this device no longer has it`() async throws {
        let account = try Account.fixture(index: 0)

        let display = try await RecoveryReveal(store: SecurityRecoveryStore()).display(for: account)

        guard case .unavailable = display else {
            Issue.record("Expected the unavailable state")
            return
        }
    }
}
