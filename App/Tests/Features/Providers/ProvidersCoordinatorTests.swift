import Foundation
import Testing
@testable import widgets

/// Checks Providers choices, custom RPCs, Helius's details, key entry, and failures with the production selection over
/// in-memory stores.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct ProvidersCoordinatorTests {
    /// A choice made in one window shows in every window's next read.
    @Test
    func `Every window checks a new provider after its next read`() async {
        let settings = StoredValue(ProviderSettings(selection: .helius))
        let keys = StoredValue<String>()
        let revisions = ProviderRevisions()
        let coordinator = ProvidersCoordinator.inMemory(settings: settings, providerKey: keys, revisions: revisions)
        let otherWindow = ProvidersCoordinator.inMemory(settings: settings, providerKey: keys, revisions: revisions)

        coordinator.select(.solana)
        await coordinator.run(coordinator.attempt)
        await coordinator.reload()
        await otherWindow.reload()

        #expect(revisions.settings.value == 1)
        #expect(coordinator.selection == .solana)
        #expect(otherWindow.selection == .solana)
        #expect(coordinator.attempt == nil)
        #expect(coordinator.error == nil)
    }

    /// Helius without a key asks for one without an error, and a saved key continues the choice that asked for it.
    /// - Parameters:
    ///   - saved: The saved choice, or `nil` while Solana is in use by default.
    ///   - settingsChanges: The setting changes every window hears about: the saved key, then any new choice.
    /// - Throws: A test prerequisite error.
    @Test(arguments: [(nil, 2), (ProviderSettings(selection: .helius), 1)])
    func `Helius is in use once its key is saved`(saved: ProviderSettings?, settingsChanges: Int) async throws {
        let revisions = ProviderRevisions()
        let coordinator = ProvidersCoordinator.inMemory(settings: StoredValue(saved), providerKey: StoredValue(),
                                                        revisions: revisions)
        coordinator.select(.helius)
        await coordinator.run(coordinator.attempt)
        let keyEntry = try #require(coordinator.keyEntry)
        #expect(coordinator.error == nil)

        try await saveKey(in: keyEntry, for: coordinator)
        let attempt = try #require(coordinator.attempt)
        await coordinator.run(attempt)
        await coordinator.reload()

        #expect(coordinator.selection == .helius)
        #expect(revisions.settings.value == settingsChanges)
        #expect(coordinator.attempt == nil)
        #expect(coordinator.error == nil)
    }

    /// A replaced key never changes the provider, even after key entry for a choice of Helius closes without a key.
    /// - Throws: A test prerequisite error.
    @Test
    func `A replaced key keeps the provider in use`() async throws {
        let settings = StoredValue(ProviderSettings(selection: .solana))
        let revisions = ProviderRevisions()
        let coordinator = ProvidersCoordinator.inMemory(settings: settings, providerKey: StoredValue(),
                                                        revisions: revisions)
        coordinator.select(.helius)
        await coordinator.run(coordinator.attempt)
        try #require(coordinator.keyEntry != nil)
        coordinator.keyEntry = nil

        coordinator.showDetails(for: .helius)
        coordinator.changeKey()
        try #require(coordinator.path == [.providerDetails, .providerKey(.add)])
        let replacement = try #require(coordinator.newKey)
        replacement.submit("replacement-key")
        await replacement.run(replacement.attempt)
        try #require(replacement.isSaved)
        coordinator.keySaved()

        #expect(!coordinator.isKeyChoiceSaved)
        #expect(coordinator.keyEntry == nil)
        #expect(await settings.value?.selection == .solana)
        #expect(coordinator.attempt == nil)
        #expect(revisions.settings.value == 1)
    }

    /// Helius's details open without a key check.
    @Test
    func `Helius's details open without a key check`() {
        let coordinator = ProvidersCoordinator.inMemory(settings: StoredValue(),
                                                        providerKey: StoredValue("fixture-key"))

        coordinator.showDetails(for: .helius)

        #expect(coordinator.path == [.providerDetails])
        #expect(coordinator.newKey == nil)
        #expect(coordinator.keyEntry == nil)
    }

    /// Back keeps a closed screen's check or RPC, so the screen keeps its content while it slides away.
    /// - Throws: A test prerequisite error.
    @Test
    func `A closed screen keeps its content`() throws {
        let url = try #require(URL(string: "https://rpc.example.com"))
        let coordinator = ProvidersCoordinator.inMemory(settings: StoredValue(), providerKey: StoredValue())

        coordinator.changeKey()
        let newKey = try #require(coordinator.newKey)
        coordinator.path.removeLast()
        coordinator.addCustomRPC()
        let setup = try #require(coordinator.setup)
        coordinator.path.removeLast()
        coordinator.showDetails(for: .custom(url))
        try #require(coordinator.path == [.customRPCDetails])
        coordinator.path.removeLast()

        #expect(coordinator.newKey === newKey)
        #expect(coordinator.setup === setup)
        #expect(coordinator.details == url)
    }

    /// Each opening of a closed screen starts a new check, so the new screen shows no earlier result and closes after
    /// its own save.
    /// - Throws: A test prerequisite error.
    @Test
    func `A screen that opens again starts a new check`() async throws {
        let coordinator = ProvidersCoordinator.inMemory(settings: StoredValue(), providerKey: StoredValue())
        coordinator.changeKey()
        let saved = try #require(coordinator.newKey)
        saved.submit("fixture-key")
        await saved.run(saved.attempt)
        try #require(saved.isSaved)
        coordinator.path.removeLast()

        coordinator.changeKey()

        #expect(coordinator.newKey !== saved)
        #expect(coordinator.newKey?.isSaved == false)
        #expect(coordinator.path == [.providerKey(.add)])
    }

    /// Key entry from Helius's details replaces a key only when one is saved, and keeps that wording while it saves.
    /// - Throws: A test prerequisite error.
    @Test
    func `Key entry from details replaces a key only when one is saved`() async throws {
        let saved = ProvidersCoordinator.inMemory(settings: StoredValue(), providerKey: StoredValue("fixture-key"))
        let missing = ProvidersCoordinator.inMemory(settings: StoredValue(), providerKey: StoredValue())
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
        let coordinator = ProvidersCoordinator.inMemory(settings: StoredValue(), providerKey: StoredValue(saved))

        await coordinator.reload()

        #expect(coordinator.keyPreview == preview)
    }

    /// A key that can't be read keeps the last preview and shows no alert, because no choice depends on it.
    /// - Throws: A test prerequisite error.
    @Test
    func `A key that can't be read keeps the last preview`() async throws {
        let keys = StoredValue("fixture-key")
        let coordinator = ProvidersCoordinator.inMemory(settings: StoredValue(), providerKey: keys)
        await coordinator.reload()
        let preview = try #require(coordinator.keyPreview)

        await keys.failLoading()
        await coordinator.reload()

        #expect(coordinator.keyPreview == preview)
        #expect(coordinator.selection == .solana)
        #expect(coordinator.error == nil)
    }

    /// A key saved in another window shows in this window's details after its next read.
    /// - Throws: A test prerequisite error.
    @Test
    func `A key changed in another window shows after the next read`() async throws {
        let settings = StoredValue<ProviderSettings>()
        let keys = StoredValue("fixture-key")
        let revisions = ProviderRevisions()
        let coordinator = ProvidersCoordinator.inMemory(settings: settings, providerKey: keys, revisions: revisions)
        let otherWindow = ProvidersCoordinator.inMemory(settings: settings, providerKey: keys, revisions: revisions)
        await coordinator.reload()
        coordinator.showDetails(for: .helius)

        otherWindow.showDetails(for: .helius)
        otherWindow.changeKey()
        let replacement = try #require(otherWindow.newKey)
        replacement.submit("replacement-key")
        await replacement.run(replacement.attempt)
        try #require(revisions.settings.value == 1)
        await coordinator.reload()

        #expect(coordinator.keyPreview == "replacement-key".formatted(.masked))
    }

    /// Solana has no details, so asking for them opens nothing.
    @Test
    func `Solana's details open nothing`() {
        let coordinator = ProvidersCoordinator.inMemory(settings: StoredValue(), providerKey: StoredValue())

        coordinator.showDetails(for: .solana)

        #expect(coordinator.path.isEmpty)
        #expect(coordinator.keyEntry == nil)
    }

    /// Taps while a choice waits are ignored, so only the first choice runs.
    /// - Throws: A test prerequisite error.
    @Test
    func `Taps during a choice are ignored`() async throws {
        let url = try #require(URL(string: "https://rpc.example.com"))
        let settings = StoredValue(ProviderSettings(selection: .helius, customRPCs: [url]))
        let coordinator = ProvidersCoordinator.inMemory(settings: settings, providerKey: StoredValue())

        coordinator.select(.solana)
        let attempt = try #require(coordinator.attempt)
        coordinator.select(.helius)
        coordinator.showDetails(for: .helius)
        coordinator.showDetails(for: .custom(url))
        coordinator.addCustomRPC()
        coordinator.changeKey()
        coordinator.remove(url)

        #expect(coordinator.attempt == attempt)
        #expect(coordinator.keyEntry == nil)
        #expect(coordinator.path.isEmpty)
        #expect(coordinator.setup == nil)
        #expect(coordinator.newKey == nil)
        await coordinator.run(attempt)
        #expect(await settings.value == ProviderSettings(selection: .solana, customRPCs: [url]))
    }

    /// Leaving the screen during a choice of Helius neither asks for the key nor explains a failure.
    /// - Throws: A test prerequisite error.
    @Test
    func `A cancelled choice opens no key entry and shows no error`() async throws {
        let coordinator = ProvidersCoordinator.inMemory(settings: StoredValue(), providerKey: StoredValue())
        coordinator.select(.helius)
        let attempt = try #require(coordinator.attempt)

        let running = Task { await coordinator.run(attempt) }
        running.cancel()
        await running.value

        #expect(coordinator.keyEntry == nil)
        #expect(coordinator.error == nil)
        #expect(coordinator.attempt == nil)
    }

    /// Leaving the screen before a read fails shows no alert when the screen returns.
    @Test
    func `A cancelled read that fails shows no error`() async {
        let coordinator = ProvidersCoordinator.inMemory(settings: StoredValue(failsLoading: true),
                                                        providerKey: StoredValue())

        let reading = Task { await coordinator.reload() }
        reading.cancel()
        await reading.value

        #expect(coordinator.error == nil)
    }

    /// Leaving the screen before a choice fails shows no alert when the screen returns.
    /// - Throws: A test prerequisite error.
    @Test
    func `A cancelled choice that fails shows no error`() async throws {
        let coordinator = ProvidersCoordinator.inMemory(settings: StoredValue(ProviderSettings(selection: .helius), failsSaving: true),
                                                        providerKey: StoredValue())
        coordinator.select(.solana)
        let attempt = try #require(coordinator.attempt)

        let running = Task { await coordinator.run(attempt) }
        running.cancel()
        await running.value

        #expect(coordinator.error == nil)
        #expect(coordinator.attempt == nil)
    }

    /// A choice that can't be saved explains it, and the provider in use stays checked.
    @Test
    func `A choice that can't be saved explains it and keeps the checkmark`() async {
        let coordinator = ProvidersCoordinator.inMemory(settings: StoredValue(ProviderSettings(selection: .helius), failsSaving: true),
                                                        providerKey: StoredValue())
        await coordinator.reload()

        coordinator.select(.solana)
        await coordinator.run(coordinator.attempt)

        #expect(coordinator.error == .selectionUnsaved)
        #expect(coordinator.selection == .helius)
        #expect(coordinator.attempt == nil)
    }

    /// Choosing the provider in use changes nothing, so a key that can't be read isn't an error.
    @Test
    func `Choosing Helius again with an unreadable key shows no error`() async {
        let coordinator = ProvidersCoordinator.inMemory(settings: StoredValue(ProviderSettings(selection: .helius)),
                                                        providerKey: StoredValue("fixture-key", failsLoading: true))
        await coordinator.reload()

        coordinator.select(.helius)
        await coordinator.run(coordinator.attempt)

        #expect(coordinator.error == nil)
        #expect(coordinator.selection == .helius)
    }

    /// A choice that can't be read explains it and keeps the provider read before checked.
    @Test
    func `A choice that can't be read explains it and keeps the checkmark`() async {
        let settings = StoredValue(ProviderSettings(selection: .helius))
        let coordinator = ProvidersCoordinator.inMemory(settings: settings, providerKey: StoredValue())
        await coordinator.reload()

        await settings.failLoading()
        await coordinator.reload()

        #expect(coordinator.error == .selectionUnreadable)
        #expect(coordinator.selection == .helius)
    }

    /// Closing after a reset drops a waiting choice, key entry, the choice that asked for a key, pushed screens and what
    /// they show, a deletion waiting for confirmation, and the last read.
    /// - Throws: A test prerequisite error.
    @Test
    func `Closing drops waiting work and key entry`() async throws {
        let url = try #require(URL(string: "https://rpc.example.com"))
        let saved = ProviderSettings(selection: .helius, customRPCs: [url])
        let settings = StoredValue(saved)
        let coordinator = ProvidersCoordinator.inMemory(settings: settings, providerKey: StoredValue())
        await coordinator.reload()
        try #require(coordinator.selection == .helius)
        try #require(coordinator.customRPCs == [url])
        coordinator.select(.helius)
        await coordinator.run(coordinator.attempt)
        let keyEntry = try #require(coordinator.keyEntry)
        coordinator.addCustomRPC()
        try #require(coordinator.setup != nil)
        coordinator.changeKey()
        try #require(coordinator.newKey != nil)
        coordinator.showDetails(for: .custom(url))
        try #require(coordinator.details == url)
        coordinator.removal = url
        coordinator.select(.solana)

        let attempt = try #require(coordinator.attempt)
        coordinator.close()
        await coordinator.run(attempt)
        // A key sheet that saves after the reset continues no choice.
        keyEntry.submit("fixture-key")
        await keyEntry.run(keyEntry.attempt)
        try #require(keyEntry.isSaved)
        coordinator.keySaved()

        #expect(!coordinator.isKeyChoiceSaved)
        #expect(coordinator.keyEntry == nil)
        #expect(coordinator.attempt == nil)
        #expect(coordinator.selection == nil)
        #expect(coordinator.customRPCs.isEmpty)
        #expect(coordinator.removal == nil)
        #expect(coordinator.path.isEmpty)
        #expect(coordinator.setup == nil)
        #expect(coordinator.newKey == nil)
        #expect(coordinator.details == nil)
        #expect(await settings.value == saved)
    }

    /// Closing after a reset drops the key preview, because the reset deleted the key without a provider change.
    /// - Throws: A test prerequisite error.
    @Test
    func `Closing drops the key preview`() async throws {
        let coordinator = ProvidersCoordinator.inMemory(settings: StoredValue(),
                                                        providerKey: StoredValue("fixture-key"))
        await coordinator.reload()
        try #require(coordinator.keyPreview != nil)

        coordinator.close()

        #expect(coordinator.keyPreview == nil)
    }

    /// Leaving Providers closes its pushed screens and drops a deletion waiting for confirmation.
    /// - Throws: A test prerequisite error.
    @Test
    func `Leaving Providers closes its screens and any waiting deletion`() throws {
        let url = try #require(URL(string: "https://rpc.example.com"))
        let coordinator = ProvidersCoordinator.inMemory(settings: StoredValue(), providerKey: StoredValue())

        coordinator.addCustomRPC()
        try #require(coordinator.path == [.customRPCSetup])
        coordinator.removal = url
        coordinator.leave()

        #expect(coordinator.path.isEmpty)
        #expect(coordinator.removal == nil)
    }

    /// Deleting a custom RPC saves the deletion and leaves every window's list on its next read, so its open details
    /// close themselves.
    /// - Throws: A test prerequisite error.
    @Test
    func `Deleting a custom RPC leaves every window's list`() async throws {
        let deleted = try #require(URL(string: "https://one.example.com"))
        let kept = try #require(URL(string: "https://two.example.com"))
        let settings = StoredValue(ProviderSettings(selection: .custom(deleted), customRPCs: [deleted, kept]))
        let revisions = ProviderRevisions()
        let coordinator = ProvidersCoordinator.inMemory(settings: settings, providerKey: StoredValue(),
                                                        revisions: revisions)
        let otherWindow = ProvidersCoordinator.inMemory(settings: settings, providerKey: StoredValue(),
                                                        revisions: revisions)
        await coordinator.reload()
        try #require(coordinator.customRPCs == [deleted, kept])

        coordinator.remove(deleted)
        await coordinator.run(coordinator.attempt)
        await coordinator.reload()
        await otherWindow.reload()

        #expect(coordinator.customRPCs == [kept])
        #expect(otherWindow.customRPCs == [kept])
        #expect(coordinator.selection == .solana)
        #expect(revisions.settings.value == 1)
        #expect(coordinator.error == nil)
    }

    /// A deletion that can't be saved explains it, and the RPC stays listed.
    /// - Throws: A test prerequisite error.
    @Test
    func `A deletion that can't be saved explains it`() async throws {
        let url = try #require(URL(string: "https://rpc.example.com"))
        let settings = StoredValue(ProviderSettings(customRPCs: [url]), failsSaving: true)
        let coordinator = ProvidersCoordinator.inMemory(settings: settings, providerKey: StoredValue())
        await coordinator.reload()

        coordinator.remove(url)
        await coordinator.run(coordinator.attempt)

        #expect(coordinator.error == .deletionUnsaved)
        #expect(coordinator.customRPCs == [url])
        #expect(await settings.value?.customRPCs == [url])
        #expect(coordinator.attempt == nil)
    }

    /// Saves a key through key entry, closes the sheet as it closes itself after a saved key, then continues the choice
    /// as the lifecycle does.
    /// - Parameters:
    ///   - keyEntry: The coordinator's open key entry.
    ///   - coordinator: The coordinator that owns key entry.
    /// - Throws: A test prerequisite error when the key isn't saved.
    private func saveKey(in keyEntry: ProviderSetupModel<ProviderConnectionError>,
                         for coordinator: ProvidersCoordinator) async throws {
        keyEntry.submit("fixture-key")
        await keyEntry.run(keyEntry.attempt)
        try #require(keyEntry.isSaved)
        coordinator.keyEntry = nil
        try #require(coordinator.isKeyChoiceSaved)
        coordinator.keySaved()
    }
}
