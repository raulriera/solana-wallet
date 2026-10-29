import Foundation
import Observation
import SwiftUI
import Testing
import Wallet
@testable import widgets

/// Exercises the production onboarding identity boundary with real SwiftUI state and task ownership.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct OnboardingIdentityTests {
    /// The window passes a new draft each time it updates, so onboarding must keep the one it started with.
    @Test
    func `An onboarding scene keeps its draft when the window passes a new one`() async throws {
        let accounts = AccountStore.inMemory()
        let recovery = OnboardingRecoveryStore()
        let providerStore = ProviderStore.inMemory()
        let gate = Suspension()
        let http = HTTPResponses.discovery(gate: gate)
        let coordinator = OnboardingCoordinator(discovery: AccountDiscovery(rpc: http.client), wallet: Wallet(),
                                                recovery: recovery, accounts: accounts)
        let providers = ProvidersCoordinator.inMemory(providerStore)
        let original = OnboardingScene(account: .constant(nil), coordinator: coordinator, providers: providers,
                                       pasteboard: NoPasteboard())
        // Read only the public model references in initial State, never recovery or input text.
        let navigation: OnboardingNavigation = try initialState("_navigation", in: original)
        let submission: ImportWalletModel = try initialState("_walletImport", in: original)
        let rendered = AsyncStream<Int>.makeStream()
        let hosted = try HostedWindow(OnboardingIdentityRoot(scene: original, generation: 0,
                                                             rendered: rendered.continuation,
                                                             providers: providerStore))
        defer {
            gate.resume()
            hosted.close()
            rendered.continuation.finish()
        }

        do {
            var renders = rendered.stream.makeAsyncIterator()
            try #require(await renders.next() == 0)
            navigation.showImport()
            submission.submit(PublicWallet.words, passphrase: "public-identity-fixture")
            await gate.waitUntilStarted()
            try #require(submission.isPending)

            let replacement = OnboardingCoordinator(discovery: AccountDiscovery(rpc: HTTPResponses.discovery().client),
                                                    wallet: Wallet(), recovery: recovery, accounts: accounts)
            hosted.host.rootView = OnboardingIdentityRoot(
                scene: OnboardingScene(account: .constant(nil), coordinator: replacement, providers: providers,
                                       pasteboard: NoPasteboard()),
                generation: 1, rendered: rendered.continuation, providers: providerStore)
            try #require(await renders.next() == 1)
            gate.resume()
            await waitForCompletion(submission)

            #expect(!(await http.wasCancelled))
            let account = try #require(coordinator.account)
            #expect(accounts.accounts.map(\.id) == [account.id])
            #expect(await recovery.saves == [account.recoveryID])
            #expect(replacement.account == nil)
            #expect(replacement.recovery == nil)
        } catch {
            // A failed prerequisite must still let the fixture task finish before the test ends.
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
