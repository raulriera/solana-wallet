import Foundation
import Testing
@testable import widgets

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct RPCCoordinatorTests {
    @Test
    func `A choice made in one window shows in every window`() async {
        let settings = StoredValue(RPCSettings(selection: .helius))
        let rpcStore = RPCStore.inMemory(settings)
        let coordinator = RPCCoordinator.inMemory(rpcStore)
        await coordinator.load()

        coordinator.select(.solana)
        await coordinator.run(coordinator.attempt)

        #expect(rpcStore.settings?.selection == .solana)
        #expect(await settings.value?.selection == .solana)
        #expect(coordinator.attempt == nil)
        #expect(coordinator.error == nil)
    }

    @Test
    func `Helius is in use once its key is saved`() async throws {
        let rpcStore = RPCStore.inMemory()
        let coordinator = RPCCoordinator.inMemory(rpcStore)
        coordinator.select(.helius)
        await coordinator.run(coordinator.attempt)
        let keyEntry = try #require(coordinator.keyEntry)
        #expect(coordinator.error == nil)

        try await saveKey(in: keyEntry, for: coordinator)
        let attempt = try #require(coordinator.attempt)
        await coordinator.run(attempt)

        #expect(rpcStore.settings?.selection == .helius)
        #expect(rpcStore.connection == .helius(key: "fixture-key"))
        #expect(coordinator.completedKeyChoice == .helius)
        #expect(coordinator.attempt == nil)
        #expect(coordinator.error == nil)
    }

    @Test
    func `Only a choice that waited for its key completes it`() async throws {
        let settings = StoredValue<RPCSettings>()
        let coordinator = RPCCoordinator.inMemory(.inMemory(settings))
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
        let coordinator = RPCCoordinator.inMemory(.inMemory(StoredValue(failsSaving: true)))
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
        let settings = StoredValue(RPCSettings(selection: .solana))
        let rpcStore = RPCStore.inMemory(settings)
        let coordinator = RPCCoordinator.inMemory(rpcStore)
        coordinator.select(.helius)
        await coordinator.run(coordinator.attempt)
        try #require(coordinator.keyEntry != nil)
        coordinator.keyEntry = nil

        coordinator.showDetails(for: .helius)
        coordinator.changeKey()
        try #require(coordinator.path == [.apiKeyDetails, .apiKey(.add)])
        let replacement = try #require(coordinator.newKey)
        replacement.submit("replacement-key")
        await replacement.run(replacement.attempt)
        try #require(replacement.isSaved)
        coordinator.keySaved()

        #expect(coordinator.keyEntry == nil)
        #expect(await settings.value?.selection == .solana)
        #expect(rpcStore.keyPreview == "replacement-key".formatted(.masked))
        #expect(coordinator.attempt == nil)
    }

    @Test
    func `Helius's details open without a key check, and Solana's open nothing`() {
        let coordinator = RPCCoordinator.inMemory(.inMemory(key: StoredValue("fixture-key")))

        coordinator.showDetails(for: .solana)
        #expect(coordinator.path.isEmpty)
        coordinator.showDetails(for: .helius)

        #expect(coordinator.path == [.apiKeyDetails])
        #expect(coordinator.newKey == nil)
        #expect(coordinator.keyEntry == nil)
    }

    @Test
    func `A closed screen keeps its content`() throws {
        let url = try #require(URL(string: "https://rpc.example.com"))
        let coordinator = RPCCoordinator.inMemory(.inMemory())

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
        let coordinator = RPCCoordinator.inMemory(.inMemory())
        coordinator.changeKey()
        let saved = try #require(coordinator.newKey)
        saved.submit("fixture-key")
        await saved.run(saved.attempt)
        try #require(saved.isSaved)
        coordinator.path.removeLast()

        coordinator.changeKey()

        #expect(coordinator.newKey !== saved)
        #expect(coordinator.newKey?.isSaved == false)
        #expect(coordinator.path == [.apiKey(.change)])
    }

    @Test
    func `Key entry from details replaces a key only when one is saved`() async throws {
        let savedStore = RPCStore.inMemory(key: StoredValue("fixture-key"))
        let missingStore = RPCStore.inMemory()
        let saved = RPCCoordinator.inMemory(savedStore)
        let missing = RPCCoordinator.inMemory(missingStore)
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

        #expect(saved.path.last == .apiKey(.change))
        #expect(missing.path.last == .apiKey(.add))
        #expect(missingStore.keyPreview == "fixture-key".formatted(.masked))
    }

    @Test
    func `Taps during a choice are ignored`() async throws {
        let url = try #require(URL(string: "https://rpc.example.com"))
        let settings = StoredValue(RPCSettings(selection: .helius, customRPCs: [url]))
        let coordinator = RPCCoordinator.inMemory(.inMemory(settings))

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
        #expect(await settings.value == RPCSettings(selection: .solana, customRPCs: [url]))
    }

    @Test(arguments: [
        (RPCSettings?.none, RPCSettings.Provider.helius, false),
        (RPCSettings(selection: .helius), .solana, true),
    ])
    func `A cancelled choice opens no key entry and shows no error, even when it can't be saved`(
        saved: RPCSettings?, choice: RPCSettings.Provider, failsSaving: Bool
    ) async throws {
        let coordinator = RPCCoordinator.inMemory(.inMemory(StoredValue(saved, failsSaving: failsSaving)))
        coordinator.select(choice)
        let attempt = try #require(coordinator.attempt)

        let running = Task { await coordinator.run(attempt) }
        running.cancel()
        await running.value

        #expect(coordinator.keyEntry == nil)
        #expect(coordinator.error == nil)
        #expect(coordinator.attempt == nil)
    }

    @Test
    func `Settings that can't be read explain it`() async {
        let coordinator = RPCCoordinator.inMemory(.inMemory(StoredValue(failsLoading: true)))

        await coordinator.load()

        #expect(coordinator.error == .selectionUnreadable)
    }

    @Test
    func `A cancelled read that fails shows no error`() async {
        let coordinator = RPCCoordinator.inMemory(.inMemory(StoredValue(failsLoading: true)))

        let reading = Task { await coordinator.load() }
        reading.cancel()
        await reading.value

        #expect(coordinator.error == nil)
    }

    @Test
    func `A choice while the settings can't be read explains the read`() async throws {
        let coordinator = RPCCoordinator.inMemory(.inMemory(StoredValue(RPCSettings(selection: .helius)),
                                                            key: StoredValue(failsLoading: true)))

        coordinator.select(.solana)
        await coordinator.run(coordinator.attempt)

        #expect(coordinator.error == .selectionUnreadable)
        #expect(coordinator.attempt == nil)
    }

    @Test
    func `Leaving RPC closes its screens`() throws {
        let coordinator = RPCCoordinator.inMemory(.inMemory())

        coordinator.addCustomRPC()
        try #require(coordinator.path == [.customRPCSetup])
        coordinator.leave()

        #expect(coordinator.path.isEmpty)
    }

    @Test
    func `Deleting a custom RPC leaves every window's list`() async throws {
        let deleted = try #require(URL(string: "https://one.example.com"))
        let kept = try #require(URL(string: "https://two.example.com"))
        let settings = StoredValue(RPCSettings(selection: .custom(deleted), customRPCs: [deleted, kept]))
        let rpcStore = RPCStore.inMemory(settings)
        let coordinator = RPCCoordinator.inMemory(rpcStore)
        await coordinator.load()

        coordinator.remove(deleted)
        await coordinator.run(coordinator.attempt)

        #expect(rpcStore.settings == RPCSettings(selection: .solana, customRPCs: [kept]))
        #expect(await settings.value == rpcStore.settings)
        #expect(coordinator.error == nil)
    }

    @Test
    func `A deletion that can't be saved explains it`() async throws {
        let url = try #require(URL(string: "https://rpc.example.com"))
        let settings = StoredValue(RPCSettings(customRPCs: [url]), failsSaving: true)
        let rpcStore = RPCStore.inMemory(settings)
        let coordinator = RPCCoordinator.inMemory(rpcStore)
        await coordinator.load()

        coordinator.remove(url)
        await coordinator.run(coordinator.attempt)

        #expect(coordinator.error == .deletionUnsaved)
        #expect(rpcStore.settings?.customRPCs == [url])
        #expect(await settings.value?.customRPCs == [url])
        #expect(coordinator.attempt == nil)
    }

    private func saveKey(in keyEntry: ProviderSetupModel<RPCConnectionError>,
                         for coordinator: RPCCoordinator) async throws {
        keyEntry.submit("fixture-key")
        await keyEntry.run(keyEntry.attempt)
        try #require(keyEntry.isSaved)
        coordinator.keyEntry = nil
        coordinator.keySaved()
        try #require(coordinator.attempt != nil)
    }
}
