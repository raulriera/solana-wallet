import Algorithms
import Testing

struct SequenceConcurrentMapTests {
    @Test
    func `Results keep the sequence's order when later elements finish first`() async throws {
        let results = try await [3, 2, 1, 0].concurrentMap { element in
            for _ in 0..<(element * 10) { await Task.yield() }
            return element * 2
        }

        #expect(results == [6, 4, 2, 0])
    }

    @Test
    func `An empty sequence has no results`() async throws {
        let results = try await [Int]().concurrentMap { $0 }

        #expect(results.isEmpty)
    }

    @Test
    func `A transform's error fails the map`() async {
        await #expect(throws: MapError.self) {
            try await [1, 2, 3].concurrentMap { element in
                if element == 2 { throw MapError() }
                return element
            }
        }
    }

    private struct MapError: Error {}
}
