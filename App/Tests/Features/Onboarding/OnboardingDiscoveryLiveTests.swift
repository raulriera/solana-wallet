import RPC
import Testing
import Wallet
@testable import widgets

@MainActor
@Suite(.tags(.network), .timeLimit(.minutes(1)))
struct OnboardingDiscoveryLiveTests {
    @Test
    func `A real mainnet lookup prepares an import without persisting it`() async throws {
        let recovery = OnboardingRecoveryStore()
        let accounts = AccountStore.inMemory()
        let coordinator = OnboardingCoordinator(discovery: AccountDiscovery(rpc: SolanaRPC(network: .mainnet)),
                                                wallet: Wallet(), recovery: recovery, accounts: accounts)

        try await coordinator.importRecovery(OnboardingCoordinatorTests.phrase, passphrase: "")

        #expect(coordinator.recovery != nil)
        #expect(coordinator.account == nil)
        #expect(coordinator.finishedAccount == nil)
        #expect(await recovery.saves.isEmpty)
        #expect(accounts.accounts.isEmpty)
        try coordinator.discard()
    }
}
