import Foundation
import Observation
import Storage
import Synchronization
import Testing

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct PersistentValueTests {
    @Test
    func `Loading shows the saved value`() async {
        let storage = StoredValue(["saved"])
        let persistent = PersistentValue(storage: storage, empty: [String]())
        #expect(persistent.phase == .unloaded)
        #expect(await storage.loads == 0)

        await persistent.load()

        #expect(persistent.phase == .loaded)
        #expect(persistent.value == ["saved"])
    }

    @Test
    func `Loading before any save shows the empty value`() async {
        let persistent = PersistentValue(storage: StoredValue<[String]>(), empty: [])

        await persistent.load()

        #expect(persistent.phase == .loaded)
        #expect(persistent.value.isEmpty)
    }

    @Test
    func `Loading during a read joins it`() async throws {
        let gate = Suspension()
        let storage = StoredValue(["saved"], unreadable: true, readGate: gate)
        let persistent = PersistentValue(storage: storage, empty: [String]())
        let first = Task.immediate { await persistent.load() }
        await gate.waitUntilStarted()

        let second = Task.immediate { await persistent.load() }
        try #require(persistent.phase == .loading)
        gate.resume()
        await first.value
        await second.value

        #expect(persistent.phase == .unreadable)
        #expect(await storage.loads == 1)
    }

    @Test
    func `A loaded value isn't read again`() async {
        let storage = StoredValue(["saved"])
        let persistent = PersistentValue(storage: storage, empty: [String]())

        await persistent.load()
        await persistent.load()

        #expect(await storage.loads == 1)
    }

    @Test
    func `An unreadable value is reported, kept, and read again`() async throws {
        let storage = StoredValue(["saved"], unreadable: true)
        let persistent = PersistentValue(storage: storage, empty: [String]())

        await persistent.load()
        #expect(persistent.phase == .unreadable)
        #expect(persistent.value.isEmpty)
        #expect(await storage.value == ["saved"])

        try await storage.save(["repaired"])
        await persistent.load()
        #expect(persistent.phase == .loaded)
        #expect(persistent.value == ["repaired"])
    }

    @Test
    func `Changes show at once and save in order`() async throws {
        let gate = Suspension()
        let storage = StoredValue(["saved"], gate: gate)
        let persistent = PersistentValue(storage: storage, empty: [String]())
        await persistent.load()

        let first = Task.immediate { try await persistent.update { $0.append("first") } }
        #expect(persistent.value == ["saved", "first"])
        await gate.waitUntilStarted()
        let second = Task.immediate { try await persistent.update { $0.append("second") } }
        #expect(persistent.value == ["saved", "first", "second"])
        #expect(await storage.value == ["saved", "first"])
        #expect(await storage.loads == 2)

        gate.resume()
        try await first.value
        try await second.value
        #expect(await storage.value == ["saved", "first", "second"])
        #expect(persistent.value == ["saved", "first", "second"])
    }

    @Test
    func `A change that can't be saved is undone`() async throws {
        let storage = StoredValue(["saved"], failsSaving: true)
        let persistent = PersistentValue(storage: storage, empty: [String]())
        await persistent.load()

        await #expect(throws: CocoaError.self) { try await persistent.update { $0.append("unsaved") } }

        #expect(persistent.value == ["saved"])
        #expect(await storage.value == ["saved"])
    }

    @Test
    func `Undoing a change keeps the changes made after it`() async throws {
        let gate = Suspension()
        let storage = StoredValue(["saved"], unreadable: true, readGate: gate)
        let persistent = PersistentValue(storage: storage, empty: [String]())
        let first = Task.immediate { try await persistent.update { $0.append("first") } }
        await gate.waitUntilStarted()
        let second = Task.immediate { try await persistent.update { $0.append("second") } }
        try #require(persistent.value == ["first", "second"])
        try await storage.save(["repaired"])

        gate.resume()
        await #expect(throws: KeychainItemError.self) { try await first.value }
        try await second.value

        #expect(persistent.value == ["repaired", "second"])
        #expect(await storage.value == ["repaired", "second"])
    }

    @Test
    func `Changes apply to the saved value`() async throws {
        let storage = StoredValue(["saved"])
        let persistent = PersistentValue(storage: storage, empty: [String]())
        await persistent.load()
        try await storage.save(["saved", "elsewhere"])

        try await persistent.update { $0.append("here") }

        #expect(await storage.value == ["saved", "elsewhere", "here"])
        #expect(persistent.value == ["saved", "elsewhere", "here"])
    }

    @Test
    func `A change that leaves the empty value saves nothing`() async throws {
        let storage = StoredValue<[String]>()
        let persistent = PersistentValue(storage: storage, empty: [String]())
        await persistent.load()

        try await persistent.update { $0.removeAll() }

        #expect(persistent.value.isEmpty)
        #expect(await storage.value == nil)
    }

    @Test
    func `Only a real change tells observers`() async throws {
        let persistent = PersistentValue(storage: StoredValue(["saved"]), empty: [String]())
        await persistent.load()
        let isNotified = Mutex(false)
        withObservationTracking {
            _ = persistent.value
            _ = persistent.phase
        } onChange: {
            isNotified.withLock { $0 = true }
        }

        try await persistent.update { $0 = ["saved"] }
        #expect(!isNotified.withLock { $0 })
        try await persistent.update { $0.append("change") }
        #expect(isNotified.withLock { $0 })
    }

    @Test
    func `Loading waits for the changes being saved`() async throws {
        let gate = Suspension()
        let storage = StoredValue(["saved"], gate: gate)
        let persistent = PersistentValue(storage: storage, empty: [String]())
        await persistent.load()
        let change = Task.immediate { try await persistent.update { $0.append("change") } }
        await gate.waitUntilStarted()

        let load = Task.immediate { await persistent.load() }
        gate.resume()
        await load.value

        #expect(await storage.value == ["saved", "change"])
        try await change.value
    }

    @Test
    func `Erasing deletes the value and returns to the empty value`() async throws {
        let storage = StoredValue(["saved"])
        let persistent = PersistentValue(storage: storage, empty: [String]())
        await persistent.load()
        let change = Task.immediate { try await persistent.update { $0.append("change") } }

        try await persistent.erase()

        try await change.value
        #expect(persistent.value.isEmpty)
        #expect(persistent.phase == .loaded)
        #expect(await storage.value == nil)
        #expect(await storage.deletions == 1)
    }

    @Test
    func `Forgetting reads as unloaded until the next read`() async throws {
        let storage = StoredValue(["saved"])
        let persistent = PersistentValue(storage: storage, empty: [String]())
        await persistent.load()

        try await persistent.forget()

        #expect(persistent.phase == .unloaded)
        #expect(await storage.value == nil)
        await persistent.load()
        #expect(persistent.phase == .loaded)
        #expect(persistent.value.isEmpty)
    }

    @Test
    func `A read that started before forgetting keeps the value hidden`() async throws {
        let gate = Suspension()
        let storage = StoredValue(["saved"], gate: gate)
        let persistent = PersistentValue(storage: storage, empty: [String]())
        await persistent.load()
        let change = Task.immediate { try await persistent.update { $0.append("change") } }
        await gate.waitUntilStarted()
        let load = Task.immediate { await persistent.load() }

        let forgetting = Task.immediate { try await persistent.forget() }
        gate.resume()
        await load.value

        #expect(persistent.phase == .unloaded)
        try await change.value
        try await forgetting.value
        #expect(persistent.phase == .unloaded)
    }

    @Test
    func `A failed forget shows the value again`() async {
        let storage = StoredValue(["saved"], failsFirstDeletion: true)
        let persistent = PersistentValue(storage: storage, empty: [String]())
        await persistent.load()

        await #expect(throws: CocoaError.self) { try await persistent.forget() }

        #expect(persistent.phase == .loaded)
        #expect(persistent.value == ["saved"])
    }

    @Test
    func `A loaded read returns the saved value`() async throws {
        let storage = StoredValue(["saved"])
        let persistent = PersistentValue(storage: storage, empty: [String]())

        #expect(try await persistent.loadedValue(orThrow: CocoaError(.fileReadUnknown)) == ["saved"])
        #expect(try await persistent.loadedValue(orThrow: CocoaError(.fileReadUnknown)) == ["saved"])

        #expect(await storage.loads == 1)
    }

    @Test
    func `A loaded read of an unreadable value throws the error`() async {
        let persistent = PersistentValue(storage: StoredValue(["saved"], unreadable: true), empty: [String]())

        await #expect(throws: CocoaError(.fileReadUnknown)) {
            try await persistent.loadedValue(orThrow: CocoaError(.fileReadUnknown))
        }
    }

    @Test
    func `A failed erase keeps the value`() async throws {
        let storage = StoredValue(["saved"], failsFirstDeletion: true)
        let persistent = PersistentValue(storage: storage, empty: [String]())
        await persistent.load()

        await #expect(throws: CocoaError.self) { try await persistent.erase() }

        #expect(persistent.value == ["saved"])
        #expect(await storage.value == ["saved"])
    }

    @Test(arguments: [
        ([PersistentValuePhase.loaded, .loading, .unreadable], PersistentValuePhase.unreadable),
        ([.loaded, .loaded], .loaded),
        ([.loaded, .unloaded, .loading], .loading),
        ([.loaded, .unloaded], .unloaded),
    ])
    func `Values that are used together share one phase`(phases: [PersistentValuePhase],
                                                          combined: PersistentValuePhase) {
        #expect(PersistentValuePhase(combining: phases) == combined)
    }
}
