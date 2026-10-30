import Foundation
import Storage
import Testing
@testable import widgets

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct ProviderStoreTests {
    @Test
    func `Loading reads the saved choice and key`() async throws {
        let custom = try #require(URL(string: "https://rpc.example.com/fixture-token"))
        let saved = ProviderSettings(selection: .helius, customRPCs: [custom])
        let settings = StoredValue(saved)
        let store = ProviderStore.inMemory(settings, key: StoredValue("fixture-key"))
        #expect(store.settings == nil)
        #expect(store.connection == nil)
        #expect(await settings.loads == 0)

        await store.load()

        #expect(store.settings == saved)
        #expect(store.keyPreview == "fixt•••••••")
        #expect(store.connection == .helius(key: "fixture-key"))
    }

    @Test
    func `Nothing saved reads as Solana without a key`() async throws {
        let store = ProviderStore.inMemory()

        #expect(try await store.loadedConnection() == .solana)

        #expect(store.settings == ProviderSettings())
        #expect(store.keyPreview == nil)
    }

    @Test(arguments: [false, true])
    func `Unreadable settings explain why`(isKeyUnreadable: Bool) async {
        let store = ProviderStore.inMemory(StoredValue(failsLoading: !isKeyUnreadable),
                                           key: StoredValue(failsLoading: isKeyUnreadable))

        await #expect(throws: ProviderClientError.settingsUnreadable) { try await store.loadedConnection() }

        #expect(store.phase == .unreadable)
        #expect(store.isRead)
        #expect(store.settings == nil)
        #expect(store.connection == nil)
    }

    @Test
    func `Helius without a key asks for the key`() async {
        let store = ProviderStore.inMemory(selection: .helius)

        await #expect(throws: ProviderClientError.missingKey) { try await store.loadedConnection() }

        #expect(store.settings?.selection == .helius)
    }

    @Test
    func `A saved key lets Helius be chosen`() async throws {
        let settings = StoredValue<ProviderSettings>()
        let store = ProviderStore.inMemory(settings, key: StoredValue("fixture-key"))

        try await store.select(.helius)

        #expect(await settings.value?.selection == .helius)
        #expect(store.connection == .helius(key: "fixture-key"))
    }

    @Test
    func `Requests read a choice before it's saved`() async throws {
        let gate = Suspension()
        let store = ProviderStore.inMemory(StoredValue(gate: gate), key: StoredValue("fixture-key"))
        await store.load()

        let selecting = Task.immediate { try await store.select(.helius) }
        await gate.waitUntilStarted()

        #expect(try await store.loadedConnection() == .helius(key: "fixture-key"))
        gate.resume()
        try await selecting.value
    }

    @Test(arguments: [nil, ProviderSettings(selection: .solana)] as [ProviderSettings?])
    func `Choosing the provider in use saves nothing`(saved: ProviderSettings?) async throws {
        let settings = StoredValue(saved, failsSaving: true)
        let store = ProviderStore.inMemory(settings)

        try await store.select(.solana)

        #expect(await settings.value == saved)
        #expect(store.connection == .solana)
    }

    @Test(arguments: [nil, ProviderSettings(selection: .helius)])
    func `Helius isn't chosen without a saved key`(saved: ProviderSettings?) async {
        let settings = StoredValue(saved)
        let store = ProviderStore.inMemory(settings)

        await #expect(throws: ProviderClientError.missingKey) { try await store.select(.helius) }

        #expect(await settings.value == saved)
        #expect(store.settings == saved ?? ProviderSettings())
    }

    @Test
    func `A cancelled choice of Helius isn't reported as a missing key`() async {
        let settings = StoredValue(ProviderSettings(selection: .solana))
        let store = ProviderStore.inMemory(settings)

        let selecting = Task { try await store.select(.helius) }
        selecting.cancel()

        await #expect(throws: CancellationError.self) { try await selecting.value }
        #expect(await settings.value?.selection == .solana)
    }

    @Test
    func `A new provider keeps the saved custom RPCs`() async throws {
        let custom = try #require(URL(string: "https://rpc.example.com/fixture-token"))
        let settings = StoredValue(ProviderSettings(selection: .custom(custom), customRPCs: [custom]))
        let store = ProviderStore.inMemory(settings)

        try await store.select(.solana)

        #expect(await settings.value == ProviderSettings(selection: .solana, customRPCs: [custom]))
    }

    @Test
    func `A choice that can't be saved changes nothing`() async {
        let saved = ProviderSettings(selection: .helius)
        let settings = StoredValue(saved, failsSaving: true)
        let store = ProviderStore.inMemory(settings, key: StoredValue("fixture-key"))

        await #expect(throws: CocoaError.self) { try await store.select(.solana) }

        #expect(await settings.value == saved)
        #expect(store.settings == saved)
        #expect(store.connection == .helius(key: "fixture-key"))
    }

    @Test
    func `A new custom RPC is saved and chosen`() async throws {
        let listed = try #require(URL(string: "https://one.example.com"))
        let custom = try #require(URL(string: "https://rpc.example.com/fixture-token"))
        let settings = StoredValue(ProviderSettings(customRPCs: [listed]))
        let store = ProviderStore.inMemory(settings)

        try await store.add(custom)

        #expect(await settings.value == ProviderSettings(selection: .custom(custom), customRPCs: [listed, custom]))
        #expect(store.connection == .custom(custom))
    }

    @Test
    func `Adding the custom RPC in use saves nothing`() async throws {
        let custom = try #require(URL(string: "https://rpc.example.com"))
        let saved = ProviderSettings(selection: .custom(custom), customRPCs: [custom])
        let settings = StoredValue(saved, failsSaving: true)
        let store = ProviderStore.inMemory(settings)

        try await store.add(custom)

        #expect(await settings.value == saved)
        #expect(store.settings == saved)
    }

    @Test
    func `Deleting the custom RPC in use switches to Solana`() async throws {
        let deleted = try #require(URL(string: "https://one.example.com"))
        let kept = try #require(URL(string: "https://two.example.com"))
        let settings = StoredValue(ProviderSettings(selection: .custom(deleted), customRPCs: [deleted, kept]))
        let store = ProviderStore.inMemory(settings)

        try await store.remove(deleted)

        #expect(await settings.value == ProviderSettings(selection: .solana, customRPCs: [kept]))
        #expect(store.connection == .solana)
    }

    @Test
    func `Deleting another custom RPC keeps the connection`() async throws {
        let deleted = try #require(URL(string: "https://one.example.com"))
        let kept = try #require(URL(string: "https://two.example.com"))
        let settings = StoredValue(ProviderSettings(selection: .custom(kept), customRPCs: [deleted, kept]))
        let store = ProviderStore.inMemory(settings)

        try await store.remove(deleted)

        #expect(store.settings == ProviderSettings(selection: .custom(kept), customRPCs: [kept]))
        #expect(await settings.value == store.settings)
        #expect(store.connection == .custom(kept))
    }

    @Test
    func `Deleting an unlisted RPC saves nothing`() async throws {
        let unlisted = try #require(URL(string: "https://one.example.com"))
        let settings = StoredValue<ProviderSettings>(failsSaving: true)
        let store = ProviderStore.inMemory(settings)

        try await store.remove(unlisted)

        #expect(await settings.value == nil)
    }

    @Test(arguments: [
        (.solana, .solana),
        (.helius, .helius(key: "fixture-key-2")),
    ] as [(ProviderSettings.Provider, ProviderClient.Endpoint)])
    func `A new key changes the connection only for Helius`(selection: ProviderSettings.Provider,
                                                            connection: ProviderClient.Endpoint) async throws {
        let key = StoredValue("fixture-key")
        let store = ProviderStore.inMemory(StoredValue(ProviderSettings(selection: selection)), key: key)

        try await store.save(key: "fixture-key-2")

        #expect(await key.value == "fixture-key-2")
        #expect(store.keyPreview == "fixt•••••••••")
        #expect(store.connection == connection)
    }

    @Test
    func `A key that can't be saved changes nothing`() async {
        let key = StoredValue("fixture-key", failsSaving: true)
        let store = ProviderStore.inMemory(StoredValue(ProviderSettings(selection: .helius)), key: key)

        await #expect(throws: CocoaError.self) { try await store.save(key: "fixture-key-2") }

        #expect(await key.value == "fixture-key")
        #expect(store.connection == .helius(key: "fixture-key"))
    }

    @Test
    func `Erasing forgets the settings until the next read`() async throws {
        let custom = try #require(URL(string: "https://rpc.example.com"))
        let settings = StoredValue(ProviderSettings(selection: .helius, customRPCs: [custom]))
        let key = StoredValue("fixture-key")
        let store = ProviderStore.inMemory(settings, key: key)
        await store.load()

        try await store.erase()

        #expect(store.phase == .unloaded)
        #expect(!store.isRead)
        #expect(store.settings == nil)
        #expect(store.connection == nil)
        #expect(await settings.value == nil)
        #expect(await key.value == nil)
        #expect(try await store.loadedConnection() == .solana)
        #expect(store.keyPreview == nil)
    }

    @Test
    func `An erasure that fails keeps the settings`() async {
        let saved = ProviderSettings(selection: .helius)
        let store = ProviderStore.inMemory(StoredValue(saved),
                                           key: StoredValue("fixture-key", failsFirstDeletion: true))
        await store.load()

        await #expect(throws: CocoaError.self) { try await store.erase() }

        #expect(store.settings == saved)
        #expect(store.connection == .helius(key: "fixture-key"))
    }

    @Test
    func `A key saved after an erase shows`() async throws {
        let store = ProviderStore.inMemory(selection: .helius, key: "fixture-key")
        await store.load()
        try await store.erase()

        try await store.save(key: "fixture-key-2")

        #expect(store.phase == .loaded)
        #expect(store.keyPreview == "fixt•••••••••")
    }

    @Test(arguments: [
        (nil, .solana, false),
        (.solana, nil, false),
        (.solana, .solana, false),
        (.helius(key: "fixture-key"), .helius(key: "fixture-key-2"), true),
        (.solana, .helius(key: "fixture-key"), true),
    ] as [(ProviderClient.Endpoint?, ProviderClient.Endpoint?, Bool)])
    func `Only a change between known connections is new`(previous: ProviderClient.Endpoint?,
                                                         connection: ProviderClient.Endpoint?, isNew: Bool) {
        #expect(ProviderClient.Endpoint.isNew(connection, after: previous) == isNew)
    }
}
