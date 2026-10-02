import Foundation
import Testing
@testable import Themes
import Synchronization

struct ConcurrencyTests {
    /// Pending cancellation completes even while another accessor occupies the background worker.
    @Test(.timeLimit(.minutes(1))) func `Pending cancellation does not wait for another import`() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.manifest()
        let presenter = HeldFilePresenter(url: fixture.source)
        NSFileCoordinator.addFilePresenter(presenter)
        defer {
            presenter.release()
            NSFileCoordinator.removeFilePresenter(presenter)
        }
        let pending = Task { @concurrent in try await PackService().read(from: fixture.source) }
        defer { pending.cancel() }
        for await _ in presenter.requested.stream {}
        let other = try Fixture()
        defer { other.remove() }
        let entered = AsyncStream<Void>.makeStream()
        let release = DispatchSemaphore(value: 0)
        let worker = Task { @concurrent in
            defer { entered.continuation.finish() }
            try await FileAccess.perform(at: other.source) { _, _ in
                entered.continuation.yield(())
                entered.continuation.finish()
                release.wait()
            }
        }
        for await _ in entered.stream {}
        let timedOut = Mutex(false)
        let watchdog = DispatchWorkItem {
            timedOut.withLock { $0 = true }
            release.signal()
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 15, execute: watchdog)
        defer { watchdog.cancel() }
        pending.cancel()
        await #expect(throws: CancellationError.self) { try await pending.value }
        #expect(!timedOut.withLock { $0 })
        release.signal()
        try await worker.value
    }

    /// A UI caller suspends while file work executes without occupying the main or task executor.
    @MainActor @Test func `File work runs outside the main actor and swift tasks`() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let result = try await FileAccess.perform(at: fixture.source) { _, _ in
            (Thread.isMainThread, withUnsafeCurrentTask { $0 != nil })
        }
        #expect(!result.0)
        #expect(!result.1)
    }

    /// Active work observes cancellation before commit and preserves success after a completed write.
    @Test(arguments: [false, true]) func `Cancellation respects active work commit state`(committed: Bool) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let entered = AsyncStream<Void>.makeStream()
        let release = DispatchSemaphore(value: 0)
        let task = Task { @concurrent in
            defer { entered.continuation.finish() }
            try await FileAccess.perform(at: fixture.source, writing: committed) { url, access in
                if committed { try Data("committed".utf8).write(to: url.appendingPathComponent("marker"), options: .atomic) }
                entered.continuation.yield(())
                entered.continuation.finish()
                // This is a synchronous test worker on the dedicated file queue, never an async task.
                release.wait()
                if !committed { try access.checkCancellation() }
            }
        }
        for await _ in entered.stream {}
        task.cancel()
        release.signal()
        if committed {
            try await task.value
            #expect(try Data(contentsOf: fixture.source.appendingPathComponent("marker")) == Data("committed".utf8))
        } else {
            await #expect(throws: CancellationError.self) { try await task.value }
        }
    }

    /// Cancellation interrupts a real pending coordinator without waiting for its presenter.
    @Test(.timeLimit(.minutes(1)), arguments: ["read", "save", "template"])
    func `Cancellation releases pending coordination`(operation: String) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.manifest()
        let service: any PackServicing = PackService()
        let pack = try await service.read(from: fixture.source)
        let before = try Data(contentsOf: fixture.source.appendingPathComponent("manifest.json"))
        let presenter = HeldFilePresenter(url: fixture.source)
        NSFileCoordinator.addFilePresenter(presenter)
        defer {
            presenter.release()
            NSFileCoordinator.removeFilePresenter(presenter)
        }
        let task = Task { @concurrent in
            switch operation {
            case "read": _ = try await service.read(from: fixture.source)
            case "save": try await service.save(pack, to: fixture.source)
            default: try await service.exportTemplate(named: "Cancelled", defaults: Fixture.defaults, to: fixture.source)
            }
        }
        // The callback is the synchronization point; this watchdog only prevents a broken
        // implementation from hanging the test runner indefinitely.
        let timedOut = Mutex(false)
        let watchdog = DispatchWorkItem {
            timedOut.withLock { $0 = true }
            presenter.release()
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 15, execute: watchdog)
        defer { watchdog.cancel() }
        for await _ in presenter.requested.stream {}
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(!timedOut.withLock { $0 })
        #expect(try Data(contentsOf: fixture.source.appendingPathComponent("manifest.json")) == before)
    }

    /// An already cancelled task cannot read a package or replace an existing destination.
    @Test(arguments: ["read", "save", "template"])
    func `Cancellation prevents file work`(operation: String) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.manifest()
        let service: any PackServicing = PackService()
        let pack = try await service.read(from: fixture.source)
        let before = try Data(contentsOf: fixture.source.appendingPathComponent("manifest.json"))
        let url = fixture.source
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            switch operation {
            case "read": _ = try await service.read(from: url)
            case "save": try await service.save(pack, to: url)
            default: try await service.exportTemplate(named: "Cancelled", defaults: Fixture.defaults, to: url)
            }
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try Data(contentsOf: url.appendingPathComponent("manifest.json")) == before)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.directory.path) == ["Source"])
    }

    /// One injected service can serve independent callers without sharing mutable operation state.
    @Test func `Simultaneous exports keep their own names and identities`() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let service: any PackServicing = PackService()
        let directory = fixture.directory
        let results = try await withThrowingTaskGroup(of: (Int, Pack).self) { group in
            for index in 0..<8 {
                group.addTask {
                    let destination = directory.appendingPathComponent("Export-\(index)")
                    try await service.exportTemplate(named: "Theme \(index)", defaults: Fixture.defaults, to: destination)
                    return (index, try await service.read(from: destination))
                }
            }
            var results: [(Int, Pack)] = []
            for try await result in group { results.append(result) }
            return results
        }
        #expect(results.count == 8)
        #expect(Set(results.map { $0.1.id }).count == 8)
        for (index, pack) in results {
            #expect(pack.name == "Theme \(index)")
            #expect(service.resolve(pack, defaults: Fixture.defaults) == Fixture.defaults)
        }
    }
}
