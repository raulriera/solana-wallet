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
        let accounts = try AccountStore(directory: directory)
        let recovery = ResetRecoveryStore()
        let keys = SavedKeys()
        let gate = Suspension()
        let http = HTTPResponses.discovery(gate: gate)
        let router = WindowRouter(initialDestination: .onboarding)
        let coordinator = OnboardingCoordinator(discovery: AccountDiscovery(rpc: http.client), wallet: Wallet(),
                                                recovery: recovery, accounts: accounts, router: router)
        let connection = HTTPResponses.keyCheck().connection(keys: keys)
        let keyRevision = ProviderKeyRevision()
        let original = OnboardingScene(coordinator: coordinator, connection: connection,
                                       keyRevision: keyRevision, pasteboard: NoPasteboard())
        // Read only the public model references in initial State, never recovery or input text.
        let navigation: OnboardingNavigation = try initialState("_navigation", in: original)
        let submission: ImportSubmission = try initialState("_importSubmission", in: original)
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

            let revision = AppResetRevision()
            try await AppReset(recovery: recovery, accounts: accounts, providerKeys: keys, revision: revision).reset()
            try #require(revision.value == 1)
            try #require(try await accounts.load().isEmpty)
            try #require(await recovery.count == 0)

            // WindowReset replaces the coordinator while an already-onboarding window keeps the same destination.
            let replacement = OnboardingCoordinator(discovery: AccountDiscovery(rpc: HTTPResponses.discovery().client),
                                                    wallet: Wallet(), recovery: recovery, accounts: accounts, router: router)
            router.route(to: .onboarding)
            hosted.host.rootView = OnboardingIdentityRoot(
                scene: OnboardingScene(coordinator: replacement, connection: connection,
                                       keyRevision: keyRevision, pasteboard: NoPasteboard()),
                generation: 1, rendered: rendered.continuation)
            try #require(await renders.next() == 1)
            gate.resume()
            await waitForCompletion(submission)

            #expect(await http.wasCancelled)
            #expect(try await accounts.load().isEmpty)
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
    private func waitForCompletion(_ submission: ImportSubmission) async {
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
