import Algorithms
import Foundation
import Testing
@testable import Themes
import Synchronization

struct ConcurrencyTests {
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

    @MainActor @Test func `File work runs outside the main actor and swift tasks`() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let result = try await FileAccess.perform(at: fixture.source) { _, _ in
            (Thread.isMainThread, withUnsafeCurrentTask { $0 != nil })
        }
        #expect(!result.0)
        #expect(!result.1)
    }

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
            default:
                try await service.exportTemplate(named: "Cancelled", defaults: Fixture.defaults, to: fixture.source)
            }
        }
        for await _ in presenter.requested.stream {}
        let timedOut = Mutex(false)
        let watchdog = DispatchWorkItem {
            timedOut.withLock { $0 = true }
            presenter.release()
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 15, execute: watchdog)
        defer { watchdog.cancel() }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(!timedOut.withLock { $0 })
        #expect(try Data(contentsOf: fixture.source.appendingPathComponent("manifest.json")) == before)
    }

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

    @Test func `Simultaneous exports keep their own names and identities`() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let service: any PackServicing = PackService()
        let directory = fixture.directory
        let packs = try await (0..<8).concurrentMap { index in
            let destination = directory.appendingPathComponent("Export-\(index)")
            try await service.exportTemplate(named: "Theme \(index)", defaults: Fixture.defaults, to: destination)
            return try await service.read(from: destination)
        }
        #expect(Set(packs.map(\.id)).count == 8)
        for (index, pack) in packs.enumerated() {
            #expect(pack.name == "Theme \(index)")
            #expect(Fixture.defaults.applying(pack) == Fixture.defaults)
        }
    }
}
