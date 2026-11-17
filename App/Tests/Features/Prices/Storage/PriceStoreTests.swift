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
    func `An unreadable choice explains why`() async {
        let store = PriceStore.inMemory(StoredValue(failsLoading: true))

        await #expect(throws: PricesError.settingsUnreadable) { try await store.loadedSettings() }

        #expect(store.phase == .unreadable)
        #expect(store.settings == nil)
    }

    @Test
    func `A choice made after an erase shows`() async throws {
        let store = PriceStore.inMemory(StoredValue(PriceSettings(selection: .off)))
        await store.load()
        try await store.erase()

        try await store.select(.jupiter)

        #expect(store.settings == PriceSettings())
    }
}
