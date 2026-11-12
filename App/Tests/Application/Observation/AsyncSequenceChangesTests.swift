import Algorithms
import Testing
@testable import widgets

struct AsyncSequenceChangesTests {
    @Test(arguments: [
        ([nil, 1, 1, 2, nil, 3, 3, 4], [2, 4]),
        ([1, 1], []),
    ] as [([Int?], [Int])])
    func `Only a change between known values is a change`(elements: [Int?], expected: [Int]) async {
        var changes: [Int] = []
        for await change in elements.async.changes() { changes.append(change) }

        #expect(changes == expected)
    }
}
