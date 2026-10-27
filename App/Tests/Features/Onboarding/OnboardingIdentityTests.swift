import Foundation
import Observation
import SwiftUI
import Testing
import Wallet
@testable import widgets

/// Exercises the production onboarding identity boundary with real SwiftUI task ownership.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct OnboardingIdentityTests {
    /// Replacing a reset coordinator must retire the old import before it can persist after reset.
    @Test
    func `Replacing a reset onboarding coordinator cancels its pending import`() async throws {
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = StoredValue<[widgets.Account]>()
        let accounts = AccountStore.inMemory(storage)
        let recovery = ResetRecoveryStore()
        let keys = StoredValue<String>()
        let gate = Suspension()
        let http = HTTPResponses.discovery(gate: gate)
        let router = WindowRouter(initialDestination: .onboarding)
        let coordinator = OnboardingCoordinator(discovery: AccountDiscovery(rpc: http.client), wallet: Wallet(),
                                                recovery: recovery, accounts: accounts, router: router)
        let providers = ProvidersCoordinator.inMemory(settings: StoredValue(), providerKey: keys)
        let original = OnboardingScene(coordinator: coordinator, providers: providers, pasteboard: NoPasteboard())
        // Read only the public model references in initial State, never recovery or input text.
        let navigation: OnboardingNavigation = try initialState("_navigation", in: original)
        let submission: ImportWalletModel = try initialState("_walletImport", in: original)
        let rendered = AsyncStream<Int>.makeStream()
        let hosted = try HostedWindow(OnboardingIdentityRoot(scene: original, generation: 0,
                                                             rendered: rendered.continuation))
        defer {
            gate.resume()
            hosted.close()
            rendered.continuation.finish()
        }

        do {
            var renders = rendered.stream.makeAsyncIterator()
            try #require(await renders.next() == 0)
            navigation.showImport()
            submission.submit(PublicWallet.words, passphrase: "public-reset-fixture")
            await gate.waitUntilStarted()
            try #require(submission.isPending)
            try #require(await http.requests.count == 1)

            let revision = Revision()
            let privateBalances = PrivateBalances.inMemory(keys: StoredValue(), notes: StoredValue(), recovery: recovery,
                                                           responses: HTTPResponses([:]))
            let appearance = AppearanceCoordinator(store: AppearanceStore(directory: directory.appending(path: "Themes")),
                                                   recovery: nil)
            try await AppReset(recovery: recovery, privateBalances: privateBalances,
                               directories: [directory], appearance: appearance,
                               stores: [ContactsFixtures.store(StoredValue()), accounts, TransactionStore.unused],
                               providerKey: keys,
                               providerSettings: StoredValue<ProviderSettings>(), revision: revision).reset()
            try #require(revision.value == 1)
            try #require(accounts.accounts.isEmpty)
            try #require(await recovery.count == 0)

            // WindowReset replaces the coordinator while an already-onboarding window keeps the same destination.
            let replacement = OnboardingCoordinator(discovery: AccountDiscovery(rpc: HTTPResponses.discovery().client),
                                                    wallet: Wallet(), recovery: recovery, accounts: accounts, router: router)
            router.route(to: .onboarding)
            hosted.host.rootView = OnboardingIdentityRoot(
                scene: OnboardingScene(coordinator: replacement, providers: providers, pasteboard: NoPasteboard()),
                generation: 1, rendered: rendered.continuation)
            try #require(await renders.next() == 1)
            gate.resume()
            await waitForCompletion(submission)

            #expect(await http.wasCancelled)
            #expect(accounts.accounts.isEmpty)
            #expect(await storage.value == nil)
            #expect(await recovery.count == 0)
            #expect(coordinator.account == nil)
            #expect(coordinator.recovery == nil)
            #expect(!coordinator.isWorking)
        } catch {
            // A failed prerequisite must still let the fixture task finish before storage cleanup.
            gate.resume()
            await waitForCompletion(submission)
            throw error
        }
    }

    /// Awaits pending-state changes until the production view task has completely unwound.
    /// - Parameter submission: The retained import whose completion must precede storage assertions or cleanup.
    private func waitForCompletion(_ submission: ImportWalletModel) async {
        while submission.isPending, !Task.isCancelled {
            let changed = AsyncStream<Void>.makeStream()
            withObservationTracking {
                _ = submission.isPending
            } onChange: {
                changed.continuation.yield(())
                changed.continuation.finish()
            }
            for await _ in changed.stream {}
        }
    }

    /// Reads a not-yet-mounted view's initial model reference without exposing production test accessors.
    /// - Parameters:
    ///   - name: The stored property wrapper's name.
    ///   - scene: The production view SwiftUI will mount.
    /// - Returns: The initial model reference SwiftUI installs for that view identity.
    /// - Throws: A failed prerequisite if the expected state property is absent.
    private func initialState<Value>(_ name: String, in scene: OnboardingScene) throws -> Value {
        let value = Mirror(reflecting: scene).children.first { $0.label == name }?.value
        let state = try #require(value as? State<Value>)
        return state.wrappedValue
    }
}
