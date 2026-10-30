import Foundation
import Testing
import Vault
import Wallet
@testable import widgets

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct WalletSetupModelTests {
    @Test
    func `Repeated taps prepare one wallet and show its words`() async throws {
        let fixture = Fixture()
        let setup = fixture.setup

        setup.create()
        let creation = try #require(setup.creation)
        setup.create()
        #expect(setup.creation == creation)
        await setup.prepare(creation)
        await setup.prepare(creation)

        #expect(setup.isPrepared)
        #expect(setup.isPending)
        #expect(setup.creation == nil)
        #expect(fixture.coordinator.recovery != nil)
        #expect(setup.error == nil)
    }

    @Test
    func `A failed preparation explains it and shows no words`() async {
        let fixture = Fixture(wallet: OnboardingWallet(error: CocoaError(.featureUnsupported)))
        let setup = fixture.setup

        setup.create()
        await setup.prepare(setup.creation)

        #expect(setup.error == .preparationFailed)
        #expect(!setup.isPrepared)
        #expect(!setup.isPending)
        #expect(fixture.coordinator.recovery == nil)
    }

    @Test
    func `A cancelled preparation leaves no draft and no alert`() async {
        let gate = Suspension()
        let fixture = Fixture(wallet: OnboardingWallet(gate: gate))
        let setup = fixture.setup
        setup.create()
        let creation = setup.creation
        let preparation = Task { await setup.prepare(creation) }
        await gate.waitUntilStarted()

        preparation.cancel()
        await preparation.value

        #expect(setup.error == nil)
        #expect(!setup.isPending)
        #expect(fixture.coordinator.recovery == nil)
        #expect(!fixture.coordinator.isWorking)
    }

    @Test
    func `Releasing a draft during preparation explains that setup is finishing`() async {
        let gate = Suspension()
        let fixture = Fixture(wallet: OnboardingWallet(gate: gate))
        let setup = fixture.setup
        setup.create()
        let creation = setup.creation
        let preparation = Task { await setup.prepare(creation) }
        await gate.waitUntilStarted()

        setup.discardDraft()
        #expect(setup.error == .stillFinishing)

        gate.resume()
        await preparation.value
        #expect(setup.isPrepared)
    }

    @Test
    func `Confirming the backup saves the wallet once`() async throws {
        let fixture = Fixture()
        let setup = fixture.setup
        setup.create()
        await setup.prepare(setup.creation)

        setup.save()
        let completion = try #require(setup.completion)
        setup.save()
        #expect(setup.completion == completion)
        await setup.complete(completion)
        await setup.complete(completion)

        #expect(fixture.coordinator.account != nil)
        #expect(await fixture.recovery.saves.count == 1)
        #expect(fixture.coordinator.finishedAccount == nil)
        #expect(setup.completion == nil)
        #expect(setup.error == nil)
    }

    @Test
    func `A failed save keeps the words for another try`() async {
        let fixture = Fixture(accounts: StoredValue(failsSaving: true))
        let setup = fixture.setup
        setup.create()
        await setup.prepare(setup.creation)

        setup.save()
        await setup.complete(setup.completion)
        #expect(setup.error == .saveFailed)
        #expect(fixture.coordinator.recovery != nil)
        #expect(fixture.coordinator.account == nil)

        await fixture.accounts.failSaving(false)
        setup.save()
        #expect(setup.error == nil)
        await setup.complete(setup.completion)
        #expect(fixture.coordinator.account != nil)
    }

    @Test
    func `Leaving the backup releases the unsaved draft`() async {
        let fixture = Fixture()
        let setup = fixture.setup
        setup.create()
        await setup.prepare(setup.creation)

        setup.leaveBackup()

        #expect(!setup.isPending)
        #expect(fixture.coordinator.recovery == nil)
        #expect(await fixture.recovery.saves.isEmpty)
        #expect(setup.error == nil)
    }

    @Test
    func `Leaving the backup during a save releases the draft once the save stops`() async {
        let gate = Suspension()
        let fixture = Fixture(recoveryGate: gate)
        let setup = fixture.setup
        setup.create()
        await setup.prepare(setup.creation)
        setup.save()
        let completion = setup.completion
        let saving = Task { await setup.complete(completion) }
        await gate.waitUntilStarted()

        setup.create()
        #expect(setup.creation == nil)
        setup.leaveBackup()
        #expect(setup.completion == nil)
        #expect(fixture.coordinator.recovery != nil)

        saving.cancel()
        await saving.value
        #expect(fixture.coordinator.recovery == nil)
        #expect(fixture.coordinator.account == nil)
        #expect(setup.error == nil)
    }

    @Test
    func `Opening waits for a pending provider change`() async throws {
        let fixture = Fixture()
        let setup = fixture.setup
        setup.create()
        await setup.prepare(setup.creation)
        setup.save()
        await setup.complete(setup.completion)
        let account = try #require(fixture.coordinator.account)

        fixture.providers.select(.solana)
        let change = try #require(fixture.providers.attempt)
        setup.open()
        #expect(fixture.coordinator.finishedAccount == nil)

        await fixture.providers.run(change)
        setup.open()
        #expect(fixture.coordinator.finishedAccount == account)
        #expect(setup.error == nil)
    }

    @Test
    func `Opening an unsaved wallet explains it`() {
        let fixture = Fixture()

        fixture.setup.open()

        #expect(fixture.setup.error == .openFailed)
        #expect(fixture.coordinator.finishedAccount == nil)
    }

    @MainActor
    private struct Fixture {
        let recovery: OnboardingRecoveryStore
        let accounts: StoredValue<[widgets.Account]>
        let providers: ProvidersCoordinator
        let coordinator: OnboardingCoordinator
        let setup: WalletSetupModel

        init(wallet: any WalletProviding = Wallet(), recoveryGate: Suspension? = nil,
             accounts: StoredValue<[widgets.Account]> = StoredValue()) {
            recovery = OnboardingRecoveryStore(gate: recoveryGate)
            self.accounts = accounts
            providers = ProvidersCoordinator.inMemory(.inMemory())
            coordinator = OnboardingCoordinator(discovery: AccountDiscovery(rpc: HTTPResponses.discovery().client),
                                                wallet: wallet, recovery: recovery,
                                                accounts: .inMemory(accounts))
            setup = WalletSetupModel(coordinator: coordinator, providers: providers)
        }
    }
}
