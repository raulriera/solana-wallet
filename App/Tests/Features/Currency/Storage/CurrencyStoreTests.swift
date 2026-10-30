import Foundation
import Storage
import Testing
@testable import RPC
@testable import widgets

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct CurrencyStoreTests {
    @Test
    func `Loading reads the saved choice`() async throws {
        let saved = CurrencySettings(rateSource: .coinbase, currencyCode: "JPY")
        let settings = StoredValue(saved)
        let store = CurrencyStore.inMemory(settings)
        #expect(store.settings == nil)
        #expect(await settings.loads == 0)

        #expect(try await store.loadedSettings() == saved)
        #expect(store.settings == saved)
    }

    @Test
    func `An unreadable choice explains why`() async {
        let store = CurrencyStore.inMemory(StoredValue(failsLoading: true))

        await #expect(throws: CurrencyError.settingsUnreadable) { try await store.loadedSettings() }

        #expect(store.phase == .unreadable)
        #expect(store.settings == nil)
    }

    @Test
    func `A new choice is saved`() async throws {
        let settings = StoredValue<CurrencySettings>()
        let store = CurrencyStore.inMemory(settings)
        await store.load()
        let expected = CurrencySettings(rateSource: .coinbase, currencyCode: "EUR")

        try await store.select(.coinbase)
        try await store.select(currencyCode: "EUR")

        #expect(store.settings == expected)
        #expect(await settings.value == expected)
    }

    @Test
    func `Prices read a change before it's saved`() async throws {
        let gate = Suspension()
        let store = CurrencyStore.inMemory(StoredValue(gate: gate))
        await store.load()

        let selecting = Task.immediate { try await store.select(currencyCode: "EUR") }
        await gate.waitUntilStarted()

        #expect(try await store.loadedSettings().currencyCode == "EUR")
        gate.resume()
        try await selecting.value
    }

    @Test(arguments: [nil, CurrencySettings(rateSource: .europeanCentralBank)] as [CurrencySettings?])
    func `An unchanged choice saves nothing`(saved: CurrencySettings?) async throws {
        let settings = StoredValue(saved)
        let store = CurrencyStore.inMemory(settings)
        await store.load()

        try await store.select(saved?.rateSource)
        try await store.select(currencyCode: nil)

        #expect(await settings.value == saved)
    }

    @Test(arguments: [
        ("JPY", .europeanCentralBank, "JPY"),
        ("ARS", .europeanCentralBank, nil),
        ("ARS", nil, "ARS"),
    ] as [(String, CurrencySettings.RateSource?, String?)])
    func `A new source keeps only a currency it serves`(chosen: String, source: CurrencySettings.RateSource?,
                                                       kept: String?) async throws {
        let settings = StoredValue(CurrencySettings(rateSource: .coinbase, currencyCode: chosen))
        let store = CurrencyStore.inMemory(settings)
        let expected = CurrencySettings(rateSource: source, currencyCode: kept)

        try await store.select(source)

        #expect(store.settings == expected)
        #expect(await settings.value == expected)
    }

    @Test
    func `A source whose currencies can't load changes nothing`() async throws {
        let saved = CurrencySettings(rateSource: .coinbase, currencyCode: "JPY")
        let settings = StoredValue(saved)
        let http = HTTPResponses.currency(error: .http(statusCode: 429, retryAfter: nil),
                                          failingMethod: CurrencyResponses.referencePath)
        let store = CurrencyStore.inMemory(settings, http: http)
        await store.load()

        await #expect(throws: RPCError.http(statusCode: 429, retryAfter: nil)) {
            try await store.select(.europeanCentralBank)
        }

        #expect(store.settings == saved)
        #expect(await settings.value == saved)
    }

    @Test(arguments: CurrencySettings.RateSource.allCases)
    func `A source lists its currencies`(source: CurrencySettings.RateSource) async throws {
        let currencies = try await CurrencyStore.inMemory().currencies(for: source)

        #expect(Set(currencies) == ["USD", "EUR", "JPY"])
    }

    @Test
    func `Erasing forgets the choice until the next read`() async throws {
        let settings = StoredValue(CurrencySettings(rateSource: .coinbase, currencyCode: "EUR"))
        let store = CurrencyStore.inMemory(settings)
        await store.load()

        try await store.erase()

        #expect(store.settings == nil)
        #expect(store.phase == .unloaded)
        #expect(await settings.value == nil)
        #expect(try await store.loadedSettings() == CurrencySettings())
    }

    @Test
    func `A currency chosen after an erase shows`() async throws {
        let store = CurrencyStore.inMemory(StoredValue(CurrencySettings(rateSource: .coinbase, currencyCode: "EUR")))
        await store.load()
        try await store.erase()

        try await store.select(currencyCode: "JPY")

        #expect(store.settings == CurrencySettings(currencyCode: "JPY"))
    }

    @Test
    func `A failed erase keeps the choice`() async throws {
        let saved = CurrencySettings(rateSource: .coinbase, currencyCode: "EUR")
        let store = CurrencyStore.inMemory(StoredValue(saved, failsFirstDeletion: true))
        await store.load()

        await #expect(throws: CocoaError.self) { try await store.erase() }

        #expect(store.settings == saved)
    }

    @Test
    func `The choice is saved in the directory`() async throws {
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CurrencyStore(directory: directory, rates: CurrencyResponses.rates())
        await store.load()

        try await store.select(.europeanCentralBank)

        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["settings.json"])
        let relaunched = CurrencyStore(directory: directory, rates: CurrencyResponses.rates())
        await relaunched.load()
        #expect(relaunched.settings == CurrencySettings(rateSource: .europeanCentralBank))
    }
}
