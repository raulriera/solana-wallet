import Foundation
import Storage
import Testing
@testable import widgets

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct PricesCoordinatorTests {
    private static let server = URL(string: "https://prices.example.com")!

    @Test
    func `A price choice is saved`() async {
        let storage = StoredValue(PriceSettings())
        let prices = PriceStore.inMemory(storage)
        let coordinator = PricesCoordinator.inMemory(prices)
        await coordinator.load()

        coordinator.select(.off)
        await coordinator.run(coordinator.attempt)

        #expect(prices.settings?.selection == .off)
        #expect(await storage.value?.selection == .off)
        #expect(coordinator.error == nil)
    }

    @Test
    func `An unreadable choice explains why`() async {
        let coordinator = PricesCoordinator.inMemory(.inMemory(StoredValue(failsLoading: true)))

        await coordinator.load()

        #expect(coordinator.error == .settingsUnreadable)
    }

    @Test
    func `A cancelled read that fails shows no error`() async {
        let coordinator = PricesCoordinator.inMemory(.inMemory(StoredValue(failsLoading: true)))

        let reading = Task { await coordinator.load() }
        reading.cancel()
        await reading.value

        #expect(coordinator.error == nil)
    }

    @Test
    func `A choice while the settings can't be read explains the read`() async {
        let coordinator = PricesCoordinator.inMemory(.inMemory(StoredValue(failsLoading: true)))

        coordinator.select(.off)
        await coordinator.run(coordinator.attempt)

        #expect(coordinator.error == .settingsUnreadable)
        #expect(coordinator.attempt == nil)
    }

    @Test
    func `A cancelled choice that fails shows no error`() async throws {
        let coordinator = PricesCoordinator.inMemory(.inMemory(StoredValue(PriceSettings(), failsSaving: true)))
        coordinator.select(.off)
        let attempt = try #require(coordinator.attempt)

        let running = Task { await coordinator.run(attempt) }
        running.cancel()
        await running.value

        #expect(coordinator.error == nil)
        #expect(coordinator.attempt == nil)
    }

    @Test
    func `A choice that can't be saved explains it and keeps the checkmark`() async {
        let prices = PriceStore.inMemory(StoredValue(PriceSettings(), failsSaving: true))
        let coordinator = PricesCoordinator.inMemory(prices)
        await coordinator.load()

        coordinator.select(.off)
        await coordinator.run(coordinator.attempt)

        #expect(coordinator.error == .settingsUnsaved)
        #expect(prices.settings?.selection == .jupiter)
    }

    @Test
    func `A new change clears the shown error`() async throws {
        let prices = PriceStore.inMemory(StoredValue(PriceSettings(), failsSaving: true))
        let coordinator = PricesCoordinator.inMemory(prices)
        await coordinator.load()
        coordinator.select(.off)
        await coordinator.run(coordinator.attempt)
        try #require(coordinator.error == .settingsUnsaved)

        coordinator.select(.off)

        #expect(coordinator.error == nil)
    }

    @Test
    func `A run for another change does nothing`() async throws {
        let storage = StoredValue(PriceSettings())
        let coordinator = PricesCoordinator.inMemory(.inMemory(storage))
        coordinator.select(.off)
        let attempt = try #require(coordinator.attempt)

        await coordinator.run(UUID())

        #expect(coordinator.attempt == attempt)
        #expect(await storage.value == PriceSettings())
    }

    @Test
    func `A change runs once while it's saving`() async throws {
        let gate = Suspension()
        let storage = StoredValue(PriceSettings(), gate: gate)
        let coordinator = PricesCoordinator.inMemory(.inMemory(storage))
        await coordinator.load()
        coordinator.select(.off)
        let attempt = try #require(coordinator.attempt)

        let running = Task.immediate { await coordinator.run(attempt) }
        await gate.waitUntilStarted()
        await coordinator.run(attempt)
        gate.resume()
        await running.value

        #expect(await storage.loads == 2)
        #expect(coordinator.attempt == nil)
    }

    @Test
    func `Adding a server opens a new check`() {
        let coordinator = PricesCoordinator.inMemory()

        coordinator.addServer()

        #expect(coordinator.path == [.serverSetup])
        #expect(coordinator.setup != nil)
    }

    @Test
    func `A screen that opens again starts a new check`() throws {
        let coordinator = PricesCoordinator.inMemory()
        coordinator.addServer()
        let first = try #require(coordinator.setup)
        coordinator.path.removeLast()

        coordinator.addServer()

        #expect(coordinator.setup !== first)
    }

    @Test
    func `A closed server screen keeps its content`() throws {
        let coordinator = PricesCoordinator.inMemory()

        coordinator.addServer()
        let setup = try #require(coordinator.setup)
        coordinator.path.removeLast()
        coordinator.showDetails(of: Self.server)
        try #require(coordinator.path == [.serverDetails])
        coordinator.path.removeLast()

        #expect(coordinator.setup === setup)
        #expect(coordinator.details == Self.server)
    }

    @Test
    func `Deleting the server in use saves the list and switches to Jupiter`() async throws {
        let kept = try #require(URL(string: "https://two.example.com"))
        let storage = StoredValue(PriceSettings(selection: .custom(Self.server), customServers: [Self.server, kept]))
        let prices = PriceStore.inMemory(storage)
        let coordinator = PricesCoordinator.inMemory(prices)
        await coordinator.load()

        coordinator.remove(Self.server)
        await coordinator.run(coordinator.attempt)

        #expect(prices.settings == PriceSettings(selection: .jupiter, customServers: [kept]))
        #expect(await storage.value == prices.settings)
        #expect(coordinator.error == nil)
    }

    @Test
    func `A deletion that can't be saved explains it`() async {
        let prices = PriceStore.inMemory(StoredValue(PriceSettings(customServers: [Self.server]), failsSaving: true))
        let coordinator = PricesCoordinator.inMemory(prices)
        await coordinator.load()

        coordinator.remove(Self.server)
        await coordinator.run(coordinator.attempt)

        #expect(coordinator.error == .deletionUnsaved)
        #expect(prices.settings?.customServers == [Self.server])
    }

    @Test
    func `Taps during a choice are ignored`() async throws {
        let storage = StoredValue(PriceSettings(customServers: [Self.server]))
        let coordinator = PricesCoordinator.inMemory(.inMemory(storage))

        coordinator.select(.off)
        let attempt = try #require(coordinator.attempt)
        coordinator.select(.custom(Self.server))
        coordinator.showDetails(of: Self.server)
        coordinator.addServer()
        coordinator.remove(Self.server)

        #expect(coordinator.attempt == attempt)
        #expect(coordinator.path.isEmpty)
        #expect(coordinator.setup == nil)
        await coordinator.run(attempt)
        #expect(await storage.value == PriceSettings(selection: .off, customServers: [Self.server]))
    }

    @Test
    func `Leaving Prices closes its screens`() {
        let coordinator = PricesCoordinator.inMemory()
        coordinator.addServer()

        coordinator.leave()

        #expect(coordinator.path.isEmpty)
    }
}
