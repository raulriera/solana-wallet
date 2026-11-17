import Foundation
import Testing
@testable import RPC

struct NoteSyncPositionTests {
    @Test(arguments: [
        ([[UInt8]]([[1], [2]]), 1, true), ([[2], [1]], 1, false), ([[1]], 1, false), ([[1], [2]], 2, false),
    ])
    func `Positions match only the same tags in order`(tags: [[UInt8]], groupCount: Int, expected: Bool) {
        let position = NoteSyncPosition(tags: [[1], [2]], groupCount: 1)

        #expect(position.matches(tags, groupCount: groupCount) == expected)
    }
}
