import Foundation
import Testing
import Themes

struct ConcurrencyTests {
    /// An already cancelled task cannot read a package or replace an existing destination.
    @Test(arguments: ["read", "export", "template"])
    func cancellationPreventsFileWork(operation: String) async throws {
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
            case "export": try await service.export(pack, defaults: Fixture.defaults, to: url)
            default: try await service.exportTemplate(named: "Cancelled", defaults: Fixture.defaults, to: url)
            }
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try Data(contentsOf: url.appendingPathComponent("manifest.json")) == before)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.directory.path) == ["Source"])
    }

    /// One injected service can serve independent callers without sharing mutable operation state.
    @Test func simultaneousExportsKeepTheirOwnNamesAndIdentities() async throws {
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
