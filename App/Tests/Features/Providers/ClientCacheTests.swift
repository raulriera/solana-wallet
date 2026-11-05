import Foundation
import Synchronization
import Testing
@testable import widgets

struct ClientCacheTests {
    @Test
    func `Only a new endpoint creates a client`() async throws {
        let made = Mutex<[String]>([])
        let cache = ClientCache<String, UUID> { endpoint in
            made.withLock { $0.append(endpoint) }
            return UUID()
        }

        let first = try await cache.client(for: "one")
        let kept = try await cache.client(for: "one")
        _ = try await cache.client(for: "two")
        let replaced = try await cache.client(for: "one")

        #expect(kept == first)
        #expect(replaced != first)
        #expect(made.withLock(\.self) == ["one", "two", "one"])
    }

    @Test
    func `An endpoint without a client can't be used`() async {
        let cache = ClientCache<String, UUID> { _ in nil }

        await #expect(throws: ProviderClientError.unusableEndpoint) { try await cache.client(for: "one") }
    }
}
