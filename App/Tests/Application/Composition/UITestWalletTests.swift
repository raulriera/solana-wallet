#if DEBUG && targetEnvironment(simulator)
import Testing
import Transactions
import Wallet
@testable import widgets

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct UITestWalletTests {
    @Test
    func `A new wallet saves its first account without network reads`() async {
        let http = HTTPResponses.discovery()
        let (onboarding, recovery, accounts) = Self.onboarding(http)

        await UITestWallet.prepare("new", with: onboarding)

        #expect(accounts.accounts.count == 1)
        #expect(await recovery.saves == accounts.accounts.map(\.recoveryID))
        #expect(await http.requests.isEmpty)
    }

    @Test
    func `Recovery words save the imported wallet's first account`() async {
        let (onboarding, recovery, accounts) = Self.onboarding()

        await UITestWallet.prepare(
            "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about",
            with: onboarding
        )

        #expect(accounts.accounts.map(\.address.value) == ["HAgk14JpMQLgt6rVgv7cBQFJWFto5Dqxi472uT3DKpqk"])
        #expect(await recovery.saves == accounts.accounts.map(\.recoveryID))
    }

    private static func onboarding(
        _ http: HTTPResponses = .discovery()
    ) -> (OnboardingCoordinator, OnboardingRecoveryStore, AccountStore) {
        let recovery = OnboardingRecoveryStore()
        let accounts = AccountStore.inMemory()
        let onboarding = OnboardingCoordinator(
            discovery: AccountDiscovery(rpc: http.client),
            wallet: Wallet(),
            recovery: recovery,
            accounts: accounts
        )
        return (onboarding, recovery, accounts)
    }
}
#endif
