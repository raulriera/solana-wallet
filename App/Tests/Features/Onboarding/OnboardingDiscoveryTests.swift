import Foundation
import RPC
import Testing
import Transactions
import Wallet
@testable import widgets

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct OnboardingDiscoveryTests {
    @Test
    func `Import retains the first funded accounts exact path`() async throws {
        let http = HTTPResponses.discovery(fundedOffsets: [1, 14])
        let recovery = OnboardingRecoveryStore()
        let accounts = AccountStore.inMemory()
        let coordinator = OnboardingCoordinator(discovery: AccountDiscovery(rpc: http.client), wallet: Wallet(),
            recovery: recovery, accounts: accounts)

        try await coordinator.importRecovery(PublicWallet.words, passphrase: "")
        #expect(await recovery.saves.isEmpty)
        let account = try await coordinator.complete()

        #expect(account.address.value == "GjJyeC1r2RgkuoCWMyPYkCWSGSGLcz266EaAkLA27AhL")
        #expect(account.path.description == "m/44'/501'/0'")
        #expect(await http.requests.count == 1)
        #expect(accounts.accounts.first?.path == account.path)
        #expect(coordinator.account?.id == account.id)
    }

    @Test
    func `An empty scan selects the default account with the original passphrase`() async throws {
        let http = HTTPResponses.discovery()
        let recovery = OnboardingRecoveryStore()
        let accounts = AccountStore.inMemory()
        let coordinator = OnboardingCoordinator(discovery: AccountDiscovery(rpc: http.client), wallet: Wallet(),
            recovery: recovery, accounts: accounts)

        try await coordinator.importRecovery(PublicWallet.words, passphrase: " TREZOR ")
        let account = try await coordinator.complete()

        #expect(account.address.value == "SbBZ94nCjPnE1w7BYq86Dn7cjHar2z6RC7Ni39t2aK4")
        #expect(account.path == .solana)
        #expect(await http.requests.count == 1)
    }

    @Test(arguments: [
        (RPCError.http(statusCode: 429, retryAfter: "3"), OnboardingCoordinatorError.discoveryRateLimited),
        (.transport(.notConnectedToInternet), .preparationFailed),
    ])
    func `Discovery failures stop preparation until an explicit retry`(
        error: RPCError, expected: OnboardingCoordinatorError
    ) async throws {
        let http = HTTPResponses.discovery(error: error)
        let recovery = OnboardingRecoveryStore()
        let accounts = AccountStore.inMemory()
        let coordinator = OnboardingCoordinator(discovery: AccountDiscovery(rpc: http.client), wallet: Wallet(),
            recovery: recovery, accounts: accounts)

        await #expect(throws: expected) {
            try await coordinator.importRecovery(PublicWallet.words, passphrase: "")
        }
        #expect(await http.requests.count == 1)
        #expect(coordinator.recovery == nil)
        #expect(coordinator.account == nil)
        #expect(!coordinator.isWorking)
        #expect(coordinator.finishedAccount == nil)
        #expect(await recovery.saves.isEmpty)
        #expect(accounts.accounts.isEmpty)

        await #expect(throws: expected) {
            try await coordinator.importRecovery(PublicWallet.words, passphrase: "")
        }
        #expect(await http.requests.count == 2)
    }
}
