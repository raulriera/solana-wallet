import Algorithms
import Testing

struct AsyncAlgorithmsTests {
    @Test
    func `Removing duplicates drops repeated elements`() async {
        var elements: [Int?] = []
        for await element in ([1, 1, nil, nil, 2, 2, 1] as [Int?]).async.removeDuplicates() { elements.append(element) }

        #expect(elements == [1, nil, 2, 1])
    }

    @Test
    func `Adjacent pairs pair each element with the one before it`() async {
        var pairs: [Pair] = []
        for await (previous, current) in ([nil, 1, 2, nil] as [Int?]).async.adjacentPairs() {
            pairs.append(Pair(previous: previous, current: current))
        }

        #expect(pairs == [Pair(previous: nil, current: 1), Pair(previous: 1, current: 2),
                          Pair(previous: 2, current: nil)])
    }

    @Test
    func `A single element makes no pair`() async {
        var count = 0
        for await _ in [1].async.adjacentPairs() { count += 1 }

        #expect(count == 0)
    }

    private struct Pair: Equatable {
        let previous: Int?
        let current: Int?
    }
}
