import Foundation
import RPC
import Testing
import Transactions
import Wallet
@testable import widgets

/// Verifies account selection at onboarding's real discovery and RPC-client boundaries.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct OnboardingDiscoveryTests {
    /// The first positive-SOL result wins in scan order, including the shorter path family.
    @Test
    func `Import retains the first funded accounts exact path`() async throws {
        let http = HTTPResponses.discovery(fundedOffsets: [1, 14])
        let recovery = OnboardingRecoveryStore()
        let accounts = OnboardingAccountStore(recovery: recovery)
        let router = WindowRouter(initialDestination: .onboarding)
        let coordinator = OnboardingCoordinator(discovery: AccountDiscovery(rpc: http.client), wallet: Wallet(),
            recovery: recovery, accounts: accounts, router: router)

        try await coordinator.importRecovery(OnboardingCoordinatorTests.phrase, passphrase: "")
        #expect(await recovery.saves.isEmpty)
        let account = try await coordinator.complete()

        #expect(account.address.value == "GjJyeC1r2RgkuoCWMyPYkCWSGSGLcz266EaAkLA27AhL")
        #expect(account.path.description == "m/44'/501'/0'")
        #expect(await http.requests.count == 1)
        #expect(await accounts.records.first?.path == account.path)
        #expect(coordinator.account?.id == account.id)
    }

    /// Only a completed empty scan selects the default first account and preserves the original passphrase.
    @Test
    func `An empty scan selects the default account with the original passphrase`() async throws {
        let http = HTTPResponses.discovery()
        let recovery = OnboardingRecoveryStore()
        let accounts = OnboardingAccountStore(recovery: recovery)
        let router = WindowRouter(initialDestination: .onboarding)
        let coordinator = OnboardingCoordinator(discovery: AccountDiscovery(rpc: http.client), wallet: Wallet(),
            recovery: recovery, accounts: accounts, router: router)

        try await coordinator.importRecovery(OnboardingCoordinatorTests.phrase, passphrase: " TREZOR ")
        let account = try await coordinator.complete()

        #expect(account.address.value == "SbBZ94nCjPnE1w7BYq86Dn7cjHar2z6RC7Ni39t2aK4")
        #expect(account.path == .solana)
        #expect(await http.requests.count == 1)
    }

    /// A failed scan cannot silently fall back, save recovery, or retry without another explicit call.
    /// - Parameters:
    ///   - failure: A transport or provider failure observed by the actual RPC client.
    ///   - expected: The payload-free failure exposed by onboarding.
    @Test(arguments: [
        (RPCError.http(statusCode: 429, retryAfter: "3"), OnboardingCoordinatorError.discoveryRateLimited),
        (.http(statusCode: 503, retryAfter: nil), .preparationFailed),
        (.transport(.notConnectedToInternet), .preparationFailed),
    ])
    func `Discovery failures stop preparation until an explicit retry`(
        failure: RPCError, expected: OnboardingCoordinatorError
    ) async throws {
        let http = HTTPResponses.discovery(failure: failure)
        let recovery = OnboardingRecoveryStore()
        let accounts = OnboardingAccountStore(recovery: recovery)
        let router = WindowRouter(initialDestination: .onboarding)
        let coordinator = OnboardingCoordinator(discovery: AccountDiscovery(rpc: http.client), wallet: Wallet(),
            recovery: recovery, accounts: accounts, router: router)

        await #expect(throws: expected) {
            try await coordinator.importRecovery(OnboardingCoordinatorTests.phrase, passphrase: "")
        }
        #expect(await http.requests.count == 1)
        #expect(coordinator.recovery == nil)
        #expect(coordinator.account == nil)
        #expect(!coordinator.isWorking)
        #expect(router.destination == .onboarding)
        #expect(await recovery.saves.isEmpty)
        #expect(await accounts.additions.isEmpty)

        await #expect(throws: expected) {
            try await coordinator.importRecovery(OnboardingCoordinatorTests.phrase, passphrase: "")
        }
        #expect(await http.requests.count == 2)
    }

    /// Performs a read-only mainnet scan using a public phrase without funding or touching saved wallets.
    @Test
    func `A real mainnet lookup prepares an import without persisting it`() async throws {
        let recovery = OnboardingRecoveryStore()
        let accounts = OnboardingAccountStore(recovery: recovery)
        let router = WindowRouter(initialDestination: .onboarding)
        let coordinator = OnboardingCoordinator(discovery: AccountDiscovery(rpc: Solana(network: .mainnet)),
            wallet: Wallet(), recovery: recovery, accounts: accounts, router: router)

        try await coordinator.importRecovery(OnboardingCoordinatorTests.phrase, passphrase: "")

        #expect(coordinator.recovery != nil)
        #expect(coordinator.account == nil)
        #expect(router.destination == .onboarding)
        #expect(await recovery.saves.isEmpty)
        #expect(await accounts.additions.isEmpty)
        try coordinator.discard()
    }
}
