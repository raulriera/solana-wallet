import Foundation
import Storage
import Testing
@testable import widgets

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct PriceStoreTests {
    private static let server = URL(string: "https://prices.example.com/v1?key=fixture-key")!

    @Test
    func `Loading reads the saved choice`() async throws {
        let saved = PriceSettings(selection: .custom(Self.server), customServers: [Self.server])
        let storage = StoredValue(saved)
        let store = PriceStore.inMemory(storage)
        #expect(store.settings == nil)

        #expect(try await store.loadedSettings() == saved)

        #expect(store.settings == saved)
        #expect(await storage.loads == 1)
    }

    @Test
    func `Nothing saved reads as Jupiter`() async throws {
        #expect(try await PriceStore.inMemory().loadedSettings() == PriceSettings())
    }

    @Test
    func `An unreadable choice explains why`() async {
        let store = PriceStore.inMemory(StoredValue(failsLoading: true))

        await #expect(throws: PricesError.settingsUnreadable) { try await store.loadedSettings() }

        #expect(store.phase == .unreadable)
        #expect(store.settings == nil)
    }

    @Test
    func `A new choice is saved`() async throws {
        let storage = StoredValue<PriceSettings>()
        let store = PriceStore.inMemory(storage)

        try await store.select(.off)

        #expect(await storage.value == PriceSettings(selection: .off))
    }

    @Test
    func `A new server is saved and chosen`() async throws {
        let storage = StoredValue(PriceSettings(selection: .off))
        let store = PriceStore.inMemory(storage)

        try await store.add(Self.server)

        let chosen = PriceSettings(selection: .custom(Self.server), customServers: [Self.server])
        #expect(await storage.value == chosen)
        #expect(store.settings == chosen)
    }

    @Test
    func `Deleting the server in use switches to Jupiter`() async throws {
        let storage = StoredValue(PriceSettings(selection: .custom(Self.server), customServers: [Self.server]))
        let store = PriceStore.inMemory(storage)

        try await store.remove(Self.server)

        #expect(await storage.value == PriceSettings())
    }

    @Test
    func `A choice that can't be saved changes nothing`() async {
        let storage = StoredValue(PriceSettings(selection: .off), failsSaving: true)
        let store = PriceStore.inMemory(storage)

        await #expect(throws: CocoaError.self) { try await store.select(.jupiter) }

        #expect(await storage.value == PriceSettings(selection: .off))
        #expect(store.settings == PriceSettings(selection: .off))
    }

    @Test
    func `Erasing forgets the choice until the next read`() async throws {
        let storage = StoredValue(PriceSettings(selection: .off))
        let store = PriceStore.inMemory(storage)
        await store.load()

        try await store.erase()

        #expect(store.settings == nil)
        #expect(store.phase == .unloaded)
        #expect(await storage.value == nil)
        #expect(try await store.loadedSettings() == PriceSettings())
    }

    @Test
    func `A choice made after an erase shows`() async throws {
        let store = PriceStore.inMemory(StoredValue(PriceSettings(selection: .off)))
        await store.load()
        try await store.erase()

        try await store.select(.jupiter)

        #expect(store.settings == PriceSettings())
    }

    @Test
    func `A failed erase keeps the choice`() async {
        let saved = PriceSettings(selection: .off)
        let store = PriceStore.inMemory(StoredValue(saved, failsFirstDeletion: true))
        await store.load()

        await #expect(throws: CocoaError.self) { try await store.erase() }

        #expect(store.settings == saved)
    }
}
