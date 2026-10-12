import Foundation
import Testing
@testable import widgets

/// Checks Providers choices, custom RPCs, Helius's details, key entry, and failures with the production selection over
/// in-memory stores.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct ProvidersFlowTests {
    /// A choice made in one window shows in every window's next read.
    @Test
    func `Every window checks a new provider after its next read`() async {
        let settings = StoredValue<ProviderSettings>()
        let keys = StoredValue<String>()
        let revision = Revision()
        let flow = ProvidersFlow.inMemory(settings: settings, providerKey: keys, revision: revision)
        let otherWindow = ProvidersFlow.inMemory(settings: settings, providerKey: keys, revision: revision)

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
        let flow = ProvidersFlow.inMemory(settings: StoredValue(ProviderSettings(selection: .solana)), providerKey: StoredValue())

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
        let flow = ProvidersFlow.inMemory(settings: StoredValue(saved), providerKey: StoredValue(), revision: revision)
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

    /// A replaced key never changes the provider, even after key entry for a choice of Helius is dismissed.
    /// - Throws: A test prerequisite error.
    @Test
    func `A replaced key keeps the provider in use`() async throws {
        let settings = StoredValue(ProviderSettings(selection: .solana))
        let revision = Revision()
        let flow = ProvidersFlow.inMemory(settings: settings, providerKey: StoredValue(), revision: revision)
        flow.select(.helius)
        await flow.run(flow.attempt)
        try #require(flow.keyEntry != nil)
        flow.keyEntry = nil

        flow.showDetails(for: .helius)
        flow.changeKey()
        try #require(flow.path == [.providerDetails, .providerKey(.add)])
        let replacement = try #require(flow.newKey)
        replacement.submit("replacement-key")
        await replacement.run(replacement.attempt)
        try #require(replacement.isSaved)

        #expect(flow.keyEntry == nil)
        #expect(await settings.value?.selection == .solana)
        #expect(flow.attempt == nil)
        #expect(revision.value == 1)
    }

    /// Helius's details open without a key check.
    @Test
    func `Helius's details open without a key check`() {
        let flow = ProvidersFlow.inMemory(settings: StoredValue(), providerKey: StoredValue("fixture-key"))

        flow.showDetails(for: .helius)

        #expect(flow.path == [.providerDetails])
        #expect(flow.newKey == nil)
        #expect(flow.keyEntry == nil)
    }

    /// Back keeps a closed screen's check or RPC, so the screen keeps its content while it slides away.
    /// - Throws: A test prerequisite error.
    @Test
    func `A closed screen keeps its content`() throws {
        let url = try #require(URL(string: "https://rpc.example.com"))
        let flow = ProvidersFlow.inMemory(settings: StoredValue(), providerKey: StoredValue())

        flow.changeKey()
        let newKey = try #require(flow.newKey)
        flow.path.removeLast()
        flow.addCustomRPC()
        let setup = try #require(flow.setup)
        flow.path.removeLast()
        flow.showDetails(for: .custom(url))
        try #require(flow.path == [.customRPCDetails])
        flow.path.removeLast()

        #expect(flow.newKey === newKey)
        #expect(flow.setup === setup)
        #expect(flow.details == url)
    }

    /// Each opening of a closed screen starts a new check, so the new screen shows no earlier result and closes after
    /// its own save.
    /// - Throws: A test prerequisite error.
    @Test
    func `A screen that opens again starts a new check`() async throws {
        let flow = ProvidersFlow.inMemory(settings: StoredValue(), providerKey: StoredValue())
        flow.changeKey()
        let saved = try #require(flow.newKey)
        saved.submit("fixture-key")
        await saved.run(saved.attempt)
        try #require(saved.isSaved)
        flow.path.removeLast()

        flow.changeKey()

        #expect(flow.newKey !== saved)
        #expect(flow.newKey?.isSaved == false)
        #expect(flow.path == [.providerKey(.add)])
    }

    /// Key entry from Helius's details replaces a key only when one is saved, and keeps that wording while it saves.
    /// - Throws: A test prerequisite error.
    @Test
    func `Key entry from details replaces a key only when one is saved`() async throws {
        let saved = ProvidersFlow.inMemory(settings: StoredValue(), providerKey: StoredValue("fixture-key"))
        let missing = ProvidersFlow.inMemory(settings: StoredValue(), providerKey: StoredValue())
        await saved.reload()
        await missing.reload()

        saved.showDetails(for: .helius)
        saved.changeKey()
        missing.showDetails(for: .helius)
        missing.changeKey()
        let added = try #require(missing.newKey)
        added.submit("fixture-key")
        await added.run(added.attempt)
        try #require(added.isSaved)
        await missing.reload()

        #expect(saved.path.last == .providerKey(.change))
        #expect(missing.path.last == .providerKey(.add))
        #expect(missing.keyPreview == "fixture-key".formatted(.masked))
    }

    /// Helius's details show only the saved key's first characters, and nothing before a key is saved.
    /// - Parameters:
    ///   - saved: The saved key, or `nil` before one is saved.
    ///   - preview: The key preview the details show.
    @Test(arguments: [("fixture-key", "fixt•••••••"), (nil, nil)] as [(String?, String?)])
    func `Helius's details show only the start of the saved key`(saved: String?, preview: String?) async {
        let flow = ProvidersFlow.inMemory(settings: StoredValue(), providerKey: StoredValue(saved))

        await flow.reload()

        #expect(flow.keyPreview == preview)
    }

    /// A key that can't be read keeps the last preview and shows no alert, because no choice depends on it.
    /// - Throws: A test prerequisite error.
    @Test
    func `A key that can't be read keeps the last preview`() async throws {
        let keys = StoredValue("fixture-key")
        let flow = ProvidersFlow.inMemory(settings: StoredValue(ProviderSettings(selection: .solana)), providerKey: keys)
        await flow.reload()
        let preview = try #require(flow.keyPreview)

        await keys.failLoading()
        await flow.reload()

        #expect(flow.keyPreview == preview)
        #expect(flow.selection == .solana)
        #expect(flow.error == nil)
    }

    /// A key saved in another window shows in this window's details after its next read.
    /// - Throws: A test prerequisite error.
    @Test
    func `A key changed in another window shows after the next read`() async throws {
        let settings = StoredValue<ProviderSettings>()
        let keys = StoredValue("fixture-key")
        let revision = Revision()
        let flow = ProvidersFlow.inMemory(settings: settings, providerKey: keys, revision: revision)
        let otherWindow = ProvidersFlow.inMemory(settings: settings, providerKey: keys, revision: revision)
        await flow.reload()
        flow.showDetails(for: .helius)

        otherWindow.showDetails(for: .helius)
        otherWindow.changeKey()
        let replacement = try #require(otherWindow.newKey)
        replacement.submit("replacement-key")
        await replacement.run(replacement.attempt)
        try #require(revision.value == 1)
        await flow.reload()

        #expect(flow.keyPreview == "replacement-key".formatted(.masked))
    }

    /// Solana has no details, so asking for them opens nothing.
    @Test
    func `Solana's details open nothing`() {
        let flow = ProvidersFlow.inMemory(settings: StoredValue(), providerKey: StoredValue())

        flow.showDetails(for: .solana)

        #expect(flow.path.isEmpty)
        #expect(flow.keyEntry == nil)
    }

    /// Taps while a choice waits are ignored, so only the first choice runs.
    /// - Throws: A test prerequisite error.
    @Test
    func `Taps during a choice are ignored`() async throws {
        let url = try #require(URL(string: "https://rpc.example.com"))
        let settings = StoredValue(ProviderSettings(customRPCs: [url]))
        let flow = ProvidersFlow.inMemory(settings: settings, providerKey: StoredValue())

        flow.select(.solana)
        let attempt = try #require(flow.attempt)
        flow.select(.helius)
        flow.showDetails(for: .helius)
        flow.showDetails(for: .custom(url))
        flow.addCustomRPC()
        flow.changeKey()
        flow.remove(url)

        #expect(flow.attempt == attempt)
        #expect(flow.keyEntry == nil)
        #expect(flow.path.isEmpty)
        #expect(flow.setup == nil)
        #expect(flow.newKey == nil)
        await flow.run(attempt)
        #expect(await settings.value == ProviderSettings(selection: .solana, customRPCs: [url]))
    }

    /// Leaving the screen during a choice of Helius neither asks for the key nor explains a failure.
    /// - Throws: A test prerequisite error.
    @Test
    func `A cancelled choice opens no key entry and shows no error`() async throws {
        let flow = ProvidersFlow.inMemory(settings: StoredValue(ProviderSettings(selection: .solana)), providerKey: StoredValue())
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
        let flow = ProvidersFlow.inMemory(settings: StoredValue(failsLoading: true), providerKey: StoredValue())

        let reading = Task { await flow.reload() }
        reading.cancel()
        await reading.value

        #expect(flow.error == nil)
    }

    /// Leaving the screen before a choice fails shows no alert when the screen returns.
    /// - Throws: A test prerequisite error.
    @Test
    func `A cancelled choice that fails shows no error`() async throws {
        let flow = ProvidersFlow.inMemory(settings: StoredValue(failsSaving: true), providerKey: StoredValue())
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
        let flow = ProvidersFlow.inMemory(settings: StoredValue(failsSaving: true), providerKey: StoredValue())
        await flow.reload()

        flow.select(.solana)
        await flow.run(flow.attempt)

        #expect(flow.error == .selectionUnsaved)
        #expect(flow.selection == .helius)
        #expect(flow.attempt == nil)
    }

    /// Choosing the provider in use changes nothing, so a key that can't be read isn't an error.
    @Test
    func `Choosing Helius again with an unreadable key shows no error`() async {
        let flow = ProvidersFlow.inMemory(settings: StoredValue(ProviderSettings(selection: .helius)),
                                          providerKey: StoredValue("fixture-key", failsLoading: true))
        await flow.reload()

        flow.select(.helius)
        await flow.run(flow.attempt)

        #expect(flow.error == nil)
        #expect(flow.selection == .helius)
    }

    /// A choice that can't be read explains it and keeps the provider read before checked.
    @Test
    func `A choice that can't be read explains it and keeps the checkmark`() async {
        let settings = StoredValue(ProviderSettings(selection: .solana))
        let flow = ProvidersFlow.inMemory(settings: settings, providerKey: StoredValue())
        await flow.reload()

        await settings.failLoading()
        await flow.reload()

        #expect(flow.error == .selectionUnreadable)
        #expect(flow.selection == .solana)
    }

    /// Closing after a reset drops a waiting choice, key entry, the choice that asked for a key, pushed screens and what
    /// they show, a deletion waiting for confirmation, and the last read.
    /// - Throws: A test prerequisite error.
    @Test
    func `Closing drops waiting work and key entry`() async throws {
        let url = try #require(URL(string: "https://rpc.example.com"))
        let settings = StoredValue(ProviderSettings(customRPCs: [url]))
        let flow = ProvidersFlow.inMemory(settings: settings, providerKey: StoredValue())
        await flow.reload()
        try #require(flow.selection == .helius)
        try #require(flow.customRPCs == [url])
        flow.select(.helius)
        await flow.run(flow.attempt)
        try #require(flow.keyEntry != nil)
        flow.addCustomRPC()
        try #require(flow.setup != nil)
        flow.changeKey()
        try #require(flow.newKey != nil)
        flow.showDetails(for: .custom(url))
        try #require(flow.details == url)
        flow.removal = url
        flow.select(.solana)

        let attempt = try #require(flow.attempt)
        flow.close()
        await flow.run(attempt)
        flow.keySaved()

        #expect(flow.keyEntry == nil)
        #expect(flow.attempt == nil)
        #expect(flow.selection == nil)
        #expect(flow.customRPCs.isEmpty)
        #expect(flow.removal == nil)
        #expect(flow.path.isEmpty)
        #expect(flow.setup == nil)
        #expect(flow.newKey == nil)
        #expect(flow.details == nil)
        #expect(await settings.value == ProviderSettings(customRPCs: [url]))
    }

    /// Closing after a reset drops the key preview, because the reset deleted the key without a provider change.
    /// - Throws: A test prerequisite error.
    @Test
    func `Closing drops the key preview`() async throws {
        let flow = ProvidersFlow.inMemory(settings: StoredValue(), providerKey: StoredValue("fixture-key"))
        await flow.reload()
        try #require(flow.keyPreview != nil)

        flow.close()

        #expect(flow.keyPreview == nil)
    }

    /// Leaving Providers closes its pushed screens and drops a deletion waiting for confirmation.
    /// - Throws: A test prerequisite error.
    @Test
    func `Leaving Providers closes its screens and any waiting deletion`() throws {
        let url = try #require(URL(string: "https://rpc.example.com"))
        let flow = ProvidersFlow.inMemory(settings: StoredValue(), providerKey: StoredValue())

        flow.addCustomRPC()
        try #require(flow.path == [.customRPCSetup])
        flow.removal = url
        flow.leave()

        #expect(flow.path.isEmpty)
        #expect(flow.removal == nil)
    }

    /// Deleting a custom RPC saves the deletion and leaves every window's list on its next read, so its open details
    /// close themselves.
    /// - Throws: A test prerequisite error.
    @Test
    func `Deleting a custom RPC leaves every window's list`() async throws {
        let deleted = try #require(URL(string: "https://one.example.com"))
        let kept = try #require(URL(string: "https://two.example.com"))
        let settings = StoredValue(ProviderSettings(selection: .custom(deleted), customRPCs: [deleted, kept]))
        let revision = Revision()
        let flow = ProvidersFlow.inMemory(settings: settings, providerKey: StoredValue(), revision: revision)
        let otherWindow = ProvidersFlow.inMemory(settings: settings, providerKey: StoredValue(), revision: revision)
        await flow.reload()
        try #require(flow.customRPCs == [deleted, kept])

        flow.remove(deleted)
        await flow.run(flow.attempt)
        await flow.reload()
        await otherWindow.reload()

        #expect(flow.customRPCs == [kept])
        #expect(otherWindow.customRPCs == [kept])
        #expect(flow.selection == .solana)
        #expect(revision.value == 1)
        #expect(flow.error == nil)
    }

    /// A deletion that can't be saved explains it, and the RPC stays listed.
    /// - Throws: A test prerequisite error.
    @Test
    func `A deletion that can't be saved explains it`() async throws {
        let url = try #require(URL(string: "https://rpc.example.com"))
        let settings = StoredValue(ProviderSettings(customRPCs: [url]), failsSaving: true)
        let flow = ProvidersFlow.inMemory(settings: settings, providerKey: StoredValue())
        await flow.reload()

        flow.remove(url)
        await flow.run(flow.attempt)

        #expect(flow.error == .deletionUnsaved)
        #expect(flow.customRPCs == [url])
        #expect(await settings.value?.customRPCs == [url])
        #expect(flow.attempt == nil)
    }

    /// Saves a key through key entry, then closes it as the sheet does after a saved key.
    /// - Parameters:
    ///   - keyEntry: The flow's open key entry.
    ///   - flow: The flow that owns key entry.
    /// - Throws: A test prerequisite error when the key isn't saved.
    private func saveKey(in keyEntry: ProviderSubmission<ProviderConnectionError>, for flow: ProvidersFlow) async throws {
        keyEntry.submit("fixture-key")
        await keyEntry.run(keyEntry.attempt)
        try #require(keyEntry.isSaved)
        flow.keySaved()
        flow.keyEntry = nil
    }
}
