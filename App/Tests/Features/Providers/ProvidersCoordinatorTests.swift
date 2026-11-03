import Foundation
import Testing
@testable import widgets

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct ProvidersCoordinatorTests {
    @Test
    func `A choice made in one window shows in every window`() async {
        let settings = StoredValue(ProviderSettings(selection: .helius))
        let providers = ProviderStore.inMemory(settings)
        let coordinator = ProvidersCoordinator.inMemory(providers)
        await coordinator.load()

        coordinator.select(.solana)
        await coordinator.run(coordinator.attempt)

        #expect(providers.settings?.selection == .solana)
        #expect(await settings.value?.selection == .solana)
        #expect(coordinator.attempt == nil)
        #expect(coordinator.error == nil)
    }

    @Test(arguments: [nil, ProviderSettings(selection: .helius)])
    func `Helius is in use once its key is saved`(saved: ProviderSettings?) async throws {
        let providers = ProviderStore.inMemory(StoredValue(saved))
        let coordinator = ProvidersCoordinator.inMemory(providers)
        coordinator.select(.helius)
        await coordinator.run(coordinator.attempt)
        let keyEntry = try #require(coordinator.keyEntry)
        #expect(coordinator.error == nil)

        try await saveKey(in: keyEntry, for: coordinator)
        let attempt = try #require(coordinator.attempt)
        await coordinator.run(attempt)

        #expect(providers.settings?.selection == .helius)
        #expect(providers.connection == .helius(key: "fixture-key"))
        #expect(coordinator.completedKeyChoice == .helius)
        #expect(coordinator.attempt == nil)
        #expect(coordinator.error == nil)
    }

    @Test
    func `Only a choice that waited for its key completes it`() async throws {
        let settings = StoredValue<ProviderSettings>()
        let coordinator = ProvidersCoordinator.inMemory(.inMemory(settings))
        coordinator.select(.helius)
        await coordinator.run(coordinator.attempt)
        try await saveKey(in: try #require(coordinator.keyEntry), for: coordinator)
        await coordinator.run(coordinator.attempt)
        try #require(coordinator.completedKeyChoice == .helius)

        coordinator.select(.solana)
        #expect(coordinator.completedKeyChoice == nil)
        await coordinator.run(coordinator.attempt)
        coordinator.select(.helius)
        await coordinator.run(coordinator.attempt)

        #expect(coordinator.completedKeyChoice == nil)
        #expect(coordinator.keyEntry == nil)
        #expect(await settings.value?.selection == .helius)
    }

    @Test
    func `A key choice that can't be saved doesn't complete`() async throws {
        let coordinator = ProvidersCoordinator.inMemory(.inMemory(StoredValue(failsSaving: true)))
        coordinator.select(.helius)
        await coordinator.run(coordinator.attempt)
        try await saveKey(in: try #require(coordinator.keyEntry), for: coordinator)

        await coordinator.run(coordinator.attempt)

        #expect(coordinator.error == .selectionUnsaved)
        #expect(coordinator.completedKeyChoice == nil)
        #expect(coordinator.attempt == nil)
    }

    @Test
    func `A replaced key keeps the provider in use`() async throws {
        let settings = StoredValue(ProviderSettings(selection: .solana))
        let providers = ProviderStore.inMemory(settings)
        let coordinator = ProvidersCoordinator.inMemory(providers)
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

        #expect(coordinator.keyEntry == nil)
        #expect(await settings.value?.selection == .solana)
        #expect(providers.keyPreview == "replacement-key".formatted(.masked))
        #expect(coordinator.attempt == nil)
    }

    @Test
    func `Helius's details open without a key check`() {
        let coordinator = ProvidersCoordinator.inMemory(.inMemory(key: StoredValue("fixture-key")))

        coordinator.showDetails(for: .helius)

        #expect(coordinator.path == [.providerDetails])
        #expect(coordinator.newKey == nil)
        #expect(coordinator.keyEntry == nil)
    }

    @Test
    func `A closed screen keeps its content`() throws {
        let url = try #require(URL(string: "https://rpc.example.com"))
        let coordinator = ProvidersCoordinator.inMemory(.inMemory())

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

    @Test
    func `A screen that opens again starts a new check`() async throws {
        let coordinator = ProvidersCoordinator.inMemory(.inMemory())
        coordinator.changeKey()
        let saved = try #require(coordinator.newKey)
        saved.submit("fixture-key")
        await saved.run(saved.attempt)
        try #require(saved.isSaved)
        coordinator.path.removeLast()

        coordinator.changeKey()

        #expect(coordinator.newKey !== saved)
        #expect(coordinator.newKey?.isSaved == false)
        #expect(coordinator.path == [.providerKey(.change)])
    }

    @Test
    func `Key entry from details replaces a key only when one is saved`() async throws {
        let savedProviders = ProviderStore.inMemory(key: StoredValue("fixture-key"))
        let missingProviders = ProviderStore.inMemory()
        let saved = ProvidersCoordinator.inMemory(savedProviders)
        let missing = ProvidersCoordinator.inMemory(missingProviders)
        await saved.load()
        await missing.load()

        saved.showDetails(for: .helius)
        saved.changeKey()
        missing.showDetails(for: .helius)
        missing.changeKey()
        let added = try #require(missing.newKey)
        added.submit("fixture-key")
        await added.run(added.attempt)
        try #require(added.isSaved)

        #expect(saved.path.last == .providerKey(.change))
        #expect(missing.path.last == .providerKey(.add))
        #expect(missingProviders.keyPreview == "fixture-key".formatted(.masked))
    }

    @Test
    func `Solana's details open nothing`() {
        let coordinator = ProvidersCoordinator.inMemory(.inMemory())

        coordinator.showDetails(for: .solana)

        #expect(coordinator.path.isEmpty)
        #expect(coordinator.keyEntry == nil)
    }

    @Test
    func `Taps during a choice are ignored`() async throws {
        let url = try #require(URL(string: "https://rpc.example.com"))
        let settings = StoredValue(ProviderSettings(selection: .helius, customRPCs: [url]))
        let coordinator = ProvidersCoordinator.inMemory(.inMemory(settings))

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

    @Test
    func `A cancelled choice opens no key entry and shows no error`() async throws {
        let coordinator = ProvidersCoordinator.inMemory(.inMemory())
        coordinator.select(.helius)
        let attempt = try #require(coordinator.attempt)

        let running = Task { await coordinator.run(attempt) }
        running.cancel()
        await running.value

        #expect(coordinator.keyEntry == nil)
        #expect(coordinator.error == nil)
        #expect(coordinator.attempt == nil)
    }

    @Test(arguments: [false, true])
    func `Settings that can't be read explain it`(isKeyUnreadable: Bool) async {
        let coordinator = ProvidersCoordinator.inMemory(.inMemory(StoredValue(failsLoading: !isKeyUnreadable),
                                                                  key: StoredValue(failsLoading: isKeyUnreadable)))

        await coordinator.load()

        #expect(coordinator.error == .selectionUnreadable)
    }

    @Test
    func `A cancelled read that fails shows no error`() async {
        let coordinator = ProvidersCoordinator.inMemory(.inMemory(StoredValue(failsLoading: true)))

        let reading = Task { await coordinator.load() }
        reading.cancel()
        await reading.value

        #expect(coordinator.error == nil)
    }

    @Test
    func `A choice while the settings can't be read explains the read`() async throws {
        let coordinator = ProvidersCoordinator.inMemory(.inMemory(StoredValue(ProviderSettings(selection: .helius)),
                                                                  key: StoredValue(failsLoading: true)))

        coordinator.select(.solana)
        await coordinator.run(coordinator.attempt)

        #expect(coordinator.error == .selectionUnreadable)
        #expect(coordinator.attempt == nil)
    }

    @Test
    func `A cancelled choice that fails shows no error`() async throws {
        let settings = StoredValue(ProviderSettings(selection: .helius), failsSaving: true)
        let coordinator = ProvidersCoordinator.inMemory(.inMemory(settings))
        coordinator.select(.solana)
        let attempt = try #require(coordinator.attempt)

        let running = Task { await coordinator.run(attempt) }
        running.cancel()
        await running.value

        #expect(coordinator.error == nil)
        #expect(coordinator.attempt == nil)
    }

    @Test
    func `A choice that can't be saved explains it and keeps the checkmark`() async {
        let providers = ProviderStore.inMemory(StoredValue(ProviderSettings(selection: .helius), failsSaving: true))
        let coordinator = ProvidersCoordinator.inMemory(providers)
        await coordinator.load()

        coordinator.select(.solana)
        await coordinator.run(coordinator.attempt)

        #expect(coordinator.error == .selectionUnsaved)
        #expect(providers.settings?.selection == .helius)
        #expect(coordinator.attempt == nil)
    }

    @Test
    func `Leaving Providers closes its screens and any waiting deletion`() throws {
        let url = try #require(URL(string: "https://rpc.example.com"))
        let coordinator = ProvidersCoordinator.inMemory(.inMemory())

        coordinator.addCustomRPC()
        try #require(coordinator.path == [.customRPCSetup])
        coordinator.removal = url
        coordinator.leave()

        #expect(coordinator.path.isEmpty)
        #expect(coordinator.removal == nil)
    }

    @Test
    func `Deleting a custom RPC leaves every window's list`() async throws {
        let deleted = try #require(URL(string: "https://one.example.com"))
        let kept = try #require(URL(string: "https://two.example.com"))
        let settings = StoredValue(ProviderSettings(selection: .custom(deleted), customRPCs: [deleted, kept]))
        let providers = ProviderStore.inMemory(settings)
        let coordinator = ProvidersCoordinator.inMemory(providers)
        await coordinator.load()

        coordinator.remove(deleted)
        await coordinator.run(coordinator.attempt)

        #expect(providers.settings == ProviderSettings(selection: .solana, customRPCs: [kept]))
        #expect(await settings.value == providers.settings)
        #expect(coordinator.error == nil)
    }

    @Test
    func `A deletion that can't be saved explains it`() async throws {
        let url = try #require(URL(string: "https://rpc.example.com"))
        let settings = StoredValue(ProviderSettings(customRPCs: [url]), failsSaving: true)
        let providers = ProviderStore.inMemory(settings)
        let coordinator = ProvidersCoordinator.inMemory(providers)
        await coordinator.load()

        coordinator.remove(url)
        await coordinator.run(coordinator.attempt)

        #expect(coordinator.error == .deletionUnsaved)
        #expect(providers.settings?.customRPCs == [url])
        #expect(await settings.value?.customRPCs == [url])
        #expect(coordinator.attempt == nil)
    }

    private func saveKey(in keyEntry: ProviderSetupModel<ProviderConnectionError>,
                         for coordinator: ProvidersCoordinator) async throws {
        keyEntry.submit("fixture-key")
        await keyEntry.run(keyEntry.attempt)
        try #require(keyEntry.isSaved)
        coordinator.keyEntry = nil
        coordinator.keySaved()
        try #require(coordinator.attempt != nil)
    }
}
