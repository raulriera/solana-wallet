import Foundation
import Testing
import Themes
@testable import widgets

@Suite(.timeLimit(.minutes(1)))
nonisolated struct CatalogTests {
    /// An installation survives source deletion and a newly created catalog instance.
    @Test func installedCopySurvivesSourceDeletionAndRelaunch() async throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let source = try fixture.source()
        let pack = try await PackService().read(from: source)
        let catalog: any ThemeCatalogProviding = try ThemeCatalog(directory: fixture.directory)
        let entry = try await catalog.install(pack)
        try FileManager.default.removeItem(at: source)
        let reopened = try ThemeCatalog(directory: fixture.directory)
        #expect(try await reopened.entries() == [entry])
        #expect(try await reopened.pack(for: entry).id == pack.id)
    }

    /// Display names never replace identity as the installation key.
    @Test func matchingNamesWithDifferentIdentitiesCoexist() async throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let catalog = try ThemeCatalog(directory: fixture.directory)
        let first = try await PackService().read(from: fixture.source())
        let second = try await PackService().read(from: fixture.source())
        _ = try await catalog.install(first)
        _ = try await catalog.install(second)
        #expect(Set(try await catalog.entries().map(\.id)) == [first.id, second.id])
    }

    /// Replacement preserves identity, requires consent, and issues a new revision.
    @Test func replacementRequiresTheCurrentEntry() async throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let catalog = try ThemeCatalog(directory: fixture.directory)
        let first = try await PackService().read(from: fixture.source())
        let old = try await catalog.install(first)
        let second = try await PackService().read(from: fixture.source(id: first.id, name: "Updated"))
        await #expect(throws: ThemeCatalog.Failure.replacementRequired(old)) { try await catalog.install(second) }
        #expect(try await catalog.pack(for: old).name == first.name)
        let updated = try await catalog.install(second, replacing: old)
        #expect(updated.id == old.id)
        #expect(updated.revision != old.revision)
        #expect(try await catalog.pack(for: updated).name == "Updated")
        await #expect(throws: ThemeCatalog.Failure.changed) { try await catalog.install(first, replacing: old) }
        await #expect(throws: ThemeCatalog.Failure.changed) { try await catalog.remove(old) }
        #expect(try await catalog.entries() == [updated])
    }

    /// Neither colliding imports nor removal can mutate a bundled theme.
    @Test func builtInsCannotBeReplacedOrRemoved() async throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let source = try fixture.source()
        let pack = try await PackService().read(from: source)
        let bundled = BundledTheme(id: pack.id, name: pack.name, url: source)
        let catalog = try ThemeCatalog(directory: fixture.directory, builtIns: [bundled])
        #expect(try await catalog.entries() == [bundled.entry])
        await #expect(throws: ThemeCatalog.Failure.builtInTheme) { try await catalog.install(pack) }
        await #expect(throws: ThemeCatalog.Failure.builtInTheme) { try await catalog.remove(bundled.entry) }
        #expect(try await catalog.pack(for: bundled.entry).id == pack.id)
        #expect(!FileManager.default.fileExists(atPath: fixture.directory.path))
    }

    /// Removal deletes only the selected custom entry, including its stored package.
    @Test func removingCustomThemePreservesOtherEntries() async throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let catalog = try ThemeCatalog(directory: fixture.directory)
        let a = try await catalog.install(PackService().read(from: fixture.source()))
        let b = try await catalog.install(PackService().read(from: fixture.source()))
        try await catalog.remove(a)
        #expect(try await catalog.entries() == [b])
        #expect(!FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent(a.id.uuidString).path))
        await #expect(throws: ThemeCatalog.Failure.changed) { try await catalog.pack(for: a) }
    }

    /// Listing remains independent of package reads, even when a stored manifest becomes unreadable.
    @Test func listingDoesNotReadPackages() async throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let catalog = try ThemeCatalog(directory: fixture.directory)
        let entry = try await catalog.install(PackService().read(from: fixture.source()))
        let package = fixture.directory.appendingPathComponent(entry.id.uuidString).appendingPathComponent(CatalogFiles.packageName)
        try FileManager.default.removeItem(at: package)
        #expect(try await catalog.entries() == [entry])
        await #expect(throws: (any Error).self) { try await catalog.pack(for: entry) }
    }

    /// Broken metadata fails explicitly rather than presenting an incomplete installed collection.
    @Test func corruptMetadataDoesNotProduceAPartialCatalog() async throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let catalog = try ThemeCatalog(directory: fixture.directory)
        let first = try await catalog.install(PackService().read(from: fixture.source()))
        _ = try await catalog.install(PackService().read(from: fixture.source()))
        let metadata = fixture.directory.appendingPathComponent(first.id.uuidString).appendingPathComponent("entry.json")
        try Data("invalid".utf8).write(to: metadata)
        await #expect(throws: DecodingError.self) { try await catalog.entries() }
    }

    /// Concurrent inserts of one identity cannot silently overwrite each other.
    @Test func concurrentImportsHaveOneWinner() async throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let pack = try await PackService().read(from: fixture.source())
        let catalog = try ThemeCatalog(directory: fixture.directory)
        let successes = await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<8 {
                group.addTask {
                    do { _ = try await catalog.install(pack); return true }
                    catch ThemeCatalog.Failure.replacementRequired { return false }
                    catch { Issue.record(error); return false }
                }
            }
            var count = 0
            for await success in group { if success { count += 1 } }
            return count
        }
        #expect(successes == 1)
        #expect(try await catalog.entries().count == 1)
    }

    /// A second catalog instance can invalidate consent while a package is being staged.
    /// - Parameter replacing: Whether the competing operations replace an existing identity.
    @Test(arguments: [false, true]) func commitRechecksRevisionAfterStaging(replacing: Bool) async throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let pack = try await PackService().read(from: fixture.source())
        let catalog = try ThemeCatalog(directory: fixture.directory)
        let original = replacing ? try await catalog.install(pack) : nil
        let staged = AsyncStream<Void>.makeStream()
        let release = AsyncStream<Void>.makeStream()
        defer { release.continuation.finish() }
        let paused = try ThemeCatalog(directory: fixture.directory, packages: InterceptedPackages {
            staged.continuation.finish()
            for await _ in release.stream {}
        })
        let pending = Task { @concurrent in try await paused.install(pack, replacing: original) }
        defer { pending.cancel() }
        for await _ in staged.stream {}
        let winner = try await catalog.install(pack, replacing: original)
        release.continuation.finish()
        let conflict: ThemeCatalog.Failure = replacing ? .changed : .replacementRequired(winner)
        await #expect(throws: conflict) { try await pending.value }
        #expect(try await catalog.entries() == [winner])
        #expect(try await catalog.pack(for: winner).id == pack.id)
    }

    /// A failed write never publishes its staged replacement or removes the prior package.
    @Test func failedStagingPreservesInstalledRevision() async throws {
        enum Failure: Error { case injected }
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let pack = try await PackService().read(from: fixture.source())
        let catalog = try ThemeCatalog(directory: fixture.directory)
        let entry = try await catalog.install(pack)
        let failing = try ThemeCatalog(directory: fixture.directory, packages: InterceptedPackages { throw Failure.injected })
        await #expect(throws: Failure.self) { try await failing.install(pack, replacing: entry) }
        #expect(try await catalog.entries() == [entry])
        #expect(try await catalog.pack(for: entry).id == pack.id)
    }

    /// Cancellation after package staging but before catalog commit preserves existing data.
    @Test func cancelledReplacementPreservesInstalledRevision() async throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let pack = try await PackService().read(from: fixture.source())
        let catalog = try ThemeCatalog(directory: fixture.directory)
        let entry = try await catalog.install(pack)
        let suspension = Suspension()
        let paused = try ThemeCatalog(directory: fixture.directory, packages: InterceptedPackages { await suspension.suspend() })
        let importing = Task { @concurrent in try await paused.install(pack, replacing: entry) }
        defer { importing.cancel() }
        await suspension.waitUntilStarted()
        importing.cancel()
        await #expect(throws: CancellationError.self) { try await importing.value }
        #expect(try await catalog.entries() == [entry])
        #expect(try await catalog.pack(for: entry).id == pack.id)
    }

    /// Catalog file work has neither main-thread execution nor a Swift task context.
    @MainActor @Test func storageRunsOutsideMainActorAndCooperativePool() async throws {
        let result = try await CatalogIO.perform { _ in (Thread.isMainThread, withUnsafeCurrentTask { $0 != nil }) }
        #expect(!result.0)
        #expect(!result.1)
    }

    /// Cancellation cannot report a failed operation after its filesystem commit has succeeded.
    @Test func cancellationAfterCommitPreservesSuccess() async throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let marker = fixture.root.appendingPathComponent("Committed")
        let entered = AsyncStream<Void>.makeStream()
        let release = DispatchSemaphore(value: 0)
        let operation = Task { @concurrent in
            try await CatalogIO.perform { checkCancellation in
                try checkCancellation()
                try Data("complete".utf8).write(to: marker, options: .atomic)
                entered.continuation.finish()
                release.wait()
                return true
            }
        }
        // Bound test-only blocking even if a regression prevents the handshake.
        let watchdog = DispatchWorkItem { release.signal(); entered.continuation.finish() }
        DispatchQueue.global().asyncAfter(deadline: .now() + 15, execute: watchdog)
        defer { watchdog.cancel(); release.signal(); operation.cancel() }
        for await _ in entered.stream {}
        operation.cancel()
        release.signal()
        #expect(try await operation.value)
        #expect(try Data(contentsOf: marker) == Data("complete".utf8))
    }
}
