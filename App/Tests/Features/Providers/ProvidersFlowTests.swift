import Foundation
import Testing
@testable import widgets

/// Checks Providers choices, key entry, and failures with the production selection over in-memory stores.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct ProvidersFlowTests {
    /// A choice made in one window shows in every window's next read.
    @Test
    func `Every window checks a new provider after its next read`() async {
        let settings = StoredValue<ProviderSettings>()
        let keys = StoredValue<String>()
        let revision = Revision()
        let flow = makeFlow(settings: settings, providerKey: keys, revision: revision)
        let otherWindow = makeFlow(settings: settings, providerKey: keys, revision: revision)

        flow.select(.solana)
        await flow.run(flow.attempt)
        await flow.reload()
        await otherWindow.reload()

        #expect(revision.value == 1)
        #expect(flow.selection == .solana)
        #expect(otherWindow.selection == .solana)
        #expect(flow.attempt == nil)
        #expect(flow.error == nil)
    }

    /// Helius without a key asks for one and keeps the provider in use.
    @Test
    func `Choosing Helius without a saved key asks for the key and keeps the provider in use`() async {
        let flow = makeFlow(settings: StoredValue(ProviderSettings(selection: .solana)), providerKey: StoredValue())

        flow.select(.helius)
        await flow.run(flow.attempt)

        #expect(flow.keyEntry != nil)
        #expect(flow.attempt == nil)
        #expect(flow.error == nil)
    }

    /// A saved key continues the choice that asked for it.
    /// - Parameters:
    ///   - saved: The saved choice, or `nil` while Helius is in use by default.
    ///   - revisions: The provider changes every window hears about: the saved key, then any new choice.
    /// - Throws: A test prerequisite error.
    @Test(arguments: [(nil, 1), (ProviderSettings(selection: .solana), 2)])
    func `Helius is in use once its key is saved`(saved: ProviderSettings?, revisions: Int) async throws {
        let revision = Revision()
        let flow = makeFlow(settings: StoredValue(saved), providerKey: StoredValue(), revision: revision)
        flow.select(.helius)
        await flow.run(flow.attempt)
        let keyEntry = try #require(flow.keyEntry)

        try await saveKey(in: keyEntry, for: flow)
        let attempt = try #require(flow.attempt)
        await flow.run(attempt)
        await flow.reload()

        #expect(flow.selection == .helius)
        #expect(revision.value == revisions)
        #expect(flow.attempt == nil)
        #expect(flow.error == nil)
    }

    /// Replacing the key never changes the provider, even after key entry for a choice of Helius is dismissed.
    /// - Throws: A test prerequisite error.
    @Test
    func `A replaced key keeps the provider in use`() async throws {
        let settings = StoredValue(ProviderSettings(selection: .solana))
        let revision = Revision()
        let flow = makeFlow(settings: settings, providerKey: StoredValue(), revision: revision)
        flow.select(.helius)
        await flow.run(flow.attempt)
        try #require(flow.keyEntry != nil)
        flow.keyEntry = nil

        flow.showDetails(for: .helius)
        let keyEntry = try #require(flow.keyEntry)
        try await saveKey(in: keyEntry, for: flow)

        #expect(await settings.value?.selection == .solana)
        #expect(flow.attempt == nil)
        #expect(revision.value == 1)
    }

    /// Solana has no details, so asking for them opens nothing.
    @Test
    func `Solana's details open nothing`() {
        let flow = makeFlow(settings: StoredValue(), providerKey: StoredValue())

        flow.showDetails(for: .solana)

        #expect(flow.keyEntry == nil)
    }

    /// Taps while a choice waits are ignored, so only the first choice runs.
    /// - Throws: A test prerequisite error.
    @Test
    func `Taps during a choice are ignored`() async throws {
        let settings = StoredValue<ProviderSettings>()
        let flow = makeFlow(settings: settings, providerKey: StoredValue())

        flow.select(.solana)
        let attempt = try #require(flow.attempt)
        flow.select(.helius)
        flow.showDetails(for: .helius)

        #expect(flow.attempt == attempt)
        #expect(flow.keyEntry == nil)
        await flow.run(attempt)
        #expect(await settings.value?.selection == .solana)
    }

    /// Leaving the screen during a choice of Helius neither asks for the key nor explains a failure.
    /// - Throws: A test prerequisite error.
    @Test
    func `A cancelled choice opens no key entry and shows no error`() async throws {
        let flow = makeFlow(settings: StoredValue(ProviderSettings(selection: .solana)), providerKey: StoredValue())
        flow.select(.helius)
        let attempt = try #require(flow.attempt)

        let running = Task { await flow.run(attempt) }
        running.cancel()
        await running.value

        #expect(flow.keyEntry == nil)
        #expect(flow.error == nil)
        #expect(flow.attempt == nil)
    }

    /// Leaving the screen before a read fails shows no alert when the screen returns.
    @Test
    func `A cancelled read that fails shows no error`() async {
        let flow = makeFlow(settings: StoredValue(failsLoading: true), providerKey: StoredValue())

        let reading = Task { await flow.reload() }
        reading.cancel()
        await reading.value

        #expect(flow.error == nil)
    }

    /// Leaving the screen before a choice fails shows no alert when the screen returns.
    /// - Throws: A test prerequisite error.
    @Test
    func `A cancelled choice that fails shows no error`() async throws {
        let flow = makeFlow(settings: StoredValue(failsSaving: true), providerKey: StoredValue())
        flow.select(.solana)
        let attempt = try #require(flow.attempt)

        let running = Task { await flow.run(attempt) }
        running.cancel()
        await running.value

        #expect(flow.error == nil)
        #expect(flow.attempt == nil)
    }

    /// A choice that can't be saved explains it, and the provider in use stays checked.
    @Test
    func `A choice that can't be saved explains it and keeps the checkmark`() async {
        let flow = makeFlow(settings: StoredValue(failsSaving: true), providerKey: StoredValue())
        await flow.reload()

        flow.select(.solana)
        await flow.run(flow.attempt)

        #expect(flow.error == .selectionUnsaved)
        #expect(flow.selection == .helius)
        #expect(flow.attempt == nil)
    }

    /// A choice that can't be read explains it and keeps the provider read before checked.
    @Test
    func `A choice that can't be read explains it and keeps the checkmark`() async {
        let settings = StoredValue(ProviderSettings(selection: .solana))
        let flow = makeFlow(settings: settings, providerKey: StoredValue())
        await flow.reload()

        await settings.failLoading()
        await flow.reload()

        #expect(flow.error == .selectionUnreadable)
        #expect(flow.selection == .solana)
    }

    /// A choice saved before the previous provider's logos fail to clear is in use, so it isn't an error.
    @Test
    func `A choice saved before its old logos fail to clear shows no error`() async {
        let revision = Revision()
        let flow = makeFlow(settings: StoredValue(), providerKey: StoredValue(),
                            portfolio: ProviderChanges(error: CocoaError(.fileWriteOutOfSpace)), revision: revision)

        flow.select(.solana)
        await flow.run(flow.attempt)
        await flow.reload()

        #expect(flow.error == nil)
        #expect(revision.value == 1)
        #expect(flow.selection == .solana)
    }

    /// Closing after a reset drops a waiting choice, key entry, the choice that asked for a key, and the last read.
    /// - Throws: A test prerequisite error.
    @Test
    func `Closing drops waiting work and key entry`() async throws {
        let settings = StoredValue<ProviderSettings>()
        let flow = makeFlow(settings: settings, providerKey: StoredValue())
        await flow.reload()
        try #require(flow.selection == .helius)
        flow.select(.helius)
        await flow.run(flow.attempt)
        try #require(flow.keyEntry != nil)
        flow.select(.solana)

        let attempt = try #require(flow.attempt)
        flow.close()
        await flow.run(attempt)
        flow.keySaved()

        #expect(flow.keyEntry == nil)
        #expect(flow.attempt == nil)
        #expect(flow.selection == nil)
        #expect(await settings.value == nil)
    }

    /// Saves a key through key entry, then closes it as the sheet does after a saved key.
    /// - Parameters:
    ///   - keyEntry: The flow's open key entry.
    ///   - flow: The flow that owns key entry.
    /// - Throws: A test prerequisite error when the key isn't saved.
    private func saveKey(in keyEntry: ProviderSubmission, for flow: ProvidersFlow) async throws {
        keyEntry.submit("fixture-key")
        await keyEntry.run(keyEntry.attempt)
        try #require(keyEntry.isSaved)
        flow.keySaved()
        flow.keyEntry = nil
    }

    /// Creates a flow around the production selection and key connection over in-memory stores.
    /// - Parameters:
    ///   - settings: The saved provider choice.
    ///   - providerKey: Helius's saved key, which key entry fills and the selection reads.
    ///   - portfolio: Records provider changes.
    ///   - revision: Counts provider changes that every window hears about.
    /// - Returns: A flow that never leaves the process.
    private func makeFlow(settings: StoredValue<ProviderSettings>, providerKey: StoredValue<String>,
                          portfolio: ProviderChanges = ProviderChanges(), revision: Revision = Revision()) -> ProvidersFlow {
        ProvidersFlow(providers: ProviderSelection(settings: settings, providerKey: providerKey, portfolio: portfolio,
                                                   revision: revision),
                      connection: HTTPResponses.keyCheck().connection(providerKey: providerKey), revision: revision)
    }
}
