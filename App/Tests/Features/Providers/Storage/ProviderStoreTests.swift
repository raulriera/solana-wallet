import Foundation
import Storage
import Testing
@testable import widgets

/// Checks that the shared provider store reads, changes, saves, and erases the choice, the custom RPCs, and Helius's
/// key, and that its connection changes only when requests go to another provider or with a new key.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct ProviderStoreTests {
    /// The store reads nothing until it loads, then shows the saved choice, a masked key, and Helius's connection.
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

    /// Before anything is saved, Solana's public RPC is in use without a key.
    @Test
    func `Nothing saved reads as Solana without a key`() async throws {
        let store = ProviderStore.inMemory()

        #expect(try await store.loadedConnection() == .solana)

        #expect(store.settings == ProviderSettings())
        #expect(store.keyPreview == nil)
    }

    /// A choice or a key that can't be read shows nothing as chosen, and reading it for a request explains why.
    /// - Parameter isKeyUnreadable: Whether the key, not the choice, can't be read.
    @Test(arguments: [false, true])
    func `Unreadable settings explain why`(isKeyUnreadable: Bool) async {
        let store = ProviderStore.inMemory(StoredValue(failsLoading: !isKeyUnreadable),
                                           key: StoredValue(failsLoading: isKeyUnreadable))

        await #expect(throws: ProviderClientError.settingsUnreadable) { try await store.loadedConnection() }

        #expect(store.phase == .unreadable)
        // The read ended, so requests go out and explain the failure.
        #expect(store.isRead)
        #expect(store.settings == nil)
        #expect(store.connection == nil)
    }

    /// Helius chosen without a saved key has no connection, so requests ask for the key.
    @Test
    func `Helius without a key asks for the key`() async {
        let store = ProviderStore.inMemory(selection: .helius)

        await #expect(throws: ProviderClientError.missingKey) { try await store.loadedConnection() }

        #expect(store.settings?.selection == .helius)
    }

    /// A saved key lets Helius replace another provider, and the connection follows.
    @Test
    func `A saved key lets Helius be chosen`() async throws {
        let settings = StoredValue<ProviderSettings>()
        let store = ProviderStore.inMemory(settings, key: StoredValue("fixture-key"))

        try await store.select(.helius)

        #expect(await settings.value?.selection == .helius)
        #expect(store.connection == .helius(key: "fixture-key"))
    }

    /// Requests read a new choice before its save finishes, so the change applies when it's made.
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

    /// Choosing the provider in use, Solana's public RPC before anything is saved, saves nothing and keeps the
    /// connection; storage that fails every save shows that nothing was saved.
    /// - Parameter saved: The choice saved before the test, if any.
    @Test(arguments: [nil, ProviderSettings(selection: .solana)] as [ProviderSettings?])
    func `Choosing the provider in use saves nothing`(saved: ProviderSettings?) async throws {
        let settings = StoredValue(saved, failsSaving: true)
        let store = ProviderStore.inMemory(settings)

        try await store.select(.solana)

        #expect(await settings.value == saved)
        #expect(store.connection == .solana)
    }

    /// Helius needs its key before anything changes, whether or not it's already in use.
    /// - Parameter saved: The saved choice, or `nil` while Solana is in use by default.
    @Test(arguments: [nil, ProviderSettings(selection: .helius)])
    func `Helius isn't chosen without a saved key`(saved: ProviderSettings?) async {
        let settings = StoredValue(saved)
        let store = ProviderStore.inMemory(settings)

        await #expect(throws: ProviderClientError.missingKey) { try await store.select(.helius) }

        #expect(await settings.value == saved)
        #expect(store.settings == saved ?? ProviderSettings())
    }

    /// A choice of Helius cancelled before its key is found stays a cancellation, so no key entry opens later.
    @Test
    func `A cancelled choice of Helius isn't reported as a missing key`() async {
        let settings = StoredValue(ProviderSettings(selection: .solana))
        let store = ProviderStore.inMemory(settings)

        let selecting = Task { try await store.select(.helius) }
        selecting.cancel()

        await #expect(throws: CancellationError.self) { try await selecting.value }
        #expect(await settings.value?.selection == .solana)
    }

    /// A new choice keeps the custom RPCs that are already saved.
    @Test
    func `A new provider keeps the saved custom RPCs`() async throws {
        let custom = try #require(URL(string: "https://rpc.example.com/fixture-token"))
        let settings = StoredValue(ProviderSettings(selection: .custom(custom), customRPCs: [custom]))
        let store = ProviderStore.inMemory(settings)

        try await store.select(.solana)

        #expect(await settings.value == ProviderSettings(selection: .solana, customRPCs: [custom]))
    }

    /// A choice that can't be saved is undone, so the previous provider stays in use everywhere.
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

    /// A checked custom RPC is saved after the listed ones and chosen.
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

    /// Adding the custom RPC in use saves nothing; storage that fails every save shows that nothing was saved.
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

    /// Deleting the custom RPC in use switches every window to Solana.
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

    /// Deleting another custom RPC keeps the provider in use and its connection; the list still changes.
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

    /// Deleting an RPC that isn't listed saves nothing; storage that fails every save shows that nothing was saved.
    @Test
    func `Deleting an unlisted RPC saves nothing`() async throws {
        let unlisted = try #require(URL(string: "https://one.example.com"))
        let settings = StoredValue<ProviderSettings>(failsSaving: true)
        let store = ProviderStore.inMemory(settings)

        try await store.remove(unlisted)

        #expect(await settings.value == nil)
    }

    /// A new key is saved and shows masked; the connection changes only while Helius is in use.
    /// - Parameters:
    ///   - selection: The provider in use.
    ///   - connection: The connection after the new key.
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

    /// A key that can't be saved is undone, so the saved key stays in use.
    @Test
    func `A key that can't be saved changes nothing`() async {
        let key = StoredValue("fixture-key", failsSaving: true)
        let store = ProviderStore.inMemory(StoredValue(ProviderSettings(selection: .helius)), key: key)

        await #expect(throws: CocoaError.self) { try await store.save(key: "fixture-key-2") }

        #expect(await key.value == "fixture-key")
        #expect(store.connection == .helius(key: "fixture-key"))
    }

    /// Erasing deletes the key and the settings and shows them as not read, as at launch; the next read finds Solana
    /// without a key.
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

    /// An erasure that can't delete the key keeps the settings as they were read.
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

    /// A key saved after an erase, as after a reset, reads the settings first, so the key shows.
    @Test
    func `A key saved after an erase shows`() async throws {
        let store = ProviderStore.inMemory(selection: .helius, key: "fixture-key")
        await store.load()
        try await store.erase()

        try await store.save(key: "fixture-key-2")

        #expect(store.phase == .loaded)
        #expect(store.keyPreview == "fixt•••••••••")
    }

    /// Only a change between two known connections is new: reading the settings and erasing them aren't, nor is an
    /// equal connection.
    /// - Parameters:
    ///   - previous: The connection before.
    ///   - connection: The connection now.
    ///   - isNew: Whether the change is a new connection.
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
