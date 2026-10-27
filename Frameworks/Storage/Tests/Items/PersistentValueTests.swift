import Foundation
import Observation
import Storage
import Synchronization
import Testing

/// Checks how a persistent value reads, saves changes in order, undoes failed changes, and erases, against in-memory
/// storage.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct PersistentValueTests {
    /// Nothing is read until the first load, which shows what's saved.
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

    /// Before anything is saved, the value is the empty value.
    @Test
    func `Loading before any save shows the empty value`() async {
        let persistent = PersistentValue(storage: StoredValue<[String]>(), empty: [])

        await persistent.load()

        #expect(persistent.phase == .loaded)
        #expect(persistent.value.isEmpty)
    }

    /// A load during a read waits for that read instead of reading again, and a later load reads nothing.
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

    /// Loading again after the value was read doesn't read it again.
    @Test
    func `A loaded value isn't read again`() async {
        let storage = StoredValue(["saved"])
        let persistent = PersistentValue(storage: storage, empty: [String]())

        await persistent.load()
        await persistent.load()

        #expect(await storage.loads == 1)
    }

    /// A value that can't be read is reported and kept, and loading again reads it again.
    @Test
    func `An unreadable value is reported, kept, and read again`() async throws {
        let storage = StoredValue(["saved"], unreadable: true)
        let persistent = PersistentValue(storage: storage, empty: [String]())

        await persistent.load()
        #expect(persistent.phase == .unreadable)
        #expect(persistent.value.isEmpty)
        #expect(await storage.value == ["saved"])

        // A save replaces the unreadable bytes, as a repaired file would.
        try await storage.save(["repaired"])
        await persistent.load()
        #expect(persistent.phase == .loaded)
        #expect(persistent.value == ["repaired"])
    }

    /// A change shows before it's saved, and the next change waits until the one before it is saved.
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
        // The second change hasn't read the saved value yet: one load, then the first change's read.
        #expect(await storage.loads == 2)

        gate.resume()
        try await first.value
        try await second.value
        #expect(await storage.value == ["saved", "first", "second"])
        #expect(persistent.value == ["saved", "first", "second"])
    }

    /// A change that can't be saved throws and is undone.
    @Test
    func `A change that can't be saved is undone`() async throws {
        let storage = StoredValue(["saved"], failsSaving: true)
        let persistent = PersistentValue(storage: storage, empty: [String]())
        await persistent.load()

        await #expect(throws: CocoaError.self) { try await persistent.update { $0.append("unsaved") } }

        #expect(persistent.value == ["saved"])
        #expect(await storage.value == ["saved"])
    }

    /// A failed change is undone without undoing the change made after it.
    @Test
    func `Undoing a change keeps the changes made after it`() async throws {
        let gate = Suspension()
        let storage = StoredValue(["saved"], unreadable: true, readGate: gate)
        let persistent = PersistentValue(storage: storage, empty: [String]())
        // The first change reads the unreadable bytes and fails once the gate opens.
        let first = Task.immediate { try await persistent.update { $0.append("first") } }
        await gate.waitUntilStarted()
        let second = Task.immediate { try await persistent.update { $0.append("second") } }
        try #require(persistent.value == ["first", "second"])
        // The save repairs the bytes, so the second change reads them.
        try await storage.save(["repaired"])

        gate.resume()
        await #expect(throws: KeychainItemError.self) { try await first.value }
        try await second.value

        #expect(persistent.value == ["repaired", "second"])
        #expect(await storage.value == ["repaired", "second"])
    }

    /// Each change runs on the saved value, so a value saved elsewhere isn't overwritten.
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

    /// Before anything is saved, a change that leaves the empty value saves nothing.
    @Test
    func `A change that leaves the empty value saves nothing`() async throws {
        let storage = StoredValue<[String]>()
        let persistent = PersistentValue(storage: storage, empty: [String]())
        await persistent.load()

        try await persistent.update { $0.removeAll() }

        #expect(persistent.value.isEmpty)
        #expect(await storage.value == nil)
    }

    /// A change or a finished save that leaves the value as it was tells no observer, and a real change does.
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

    /// Loading returns once the changes made before it are saved.
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

    /// Erasing deletes what's saved, after the changes made before it, and returns to the empty value.
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

    /// A deletion that fails keeps the value.
    @Test
    func `A failed erase keeps the value`() async throws {
        let storage = StoredValue(["saved"], failsFirstDeletion: true)
        let persistent = PersistentValue(storage: storage, empty: [String]())
        await persistent.load()

        await #expect(throws: CocoaError.self) { try await persistent.erase() }

        #expect(persistent.value == ["saved"])
        #expect(await storage.value == ["saved"])
    }
}
