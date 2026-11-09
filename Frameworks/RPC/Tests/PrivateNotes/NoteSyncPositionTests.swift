import Foundation
import Testing
@testable import RPC

struct NoteSyncPositionTests {
    @Test
    func `Positions survive storage`() throws {
        let position = NoteSyncPosition(
            tags: [[1], [2]],
            transactionCheckpoints: [IndexerCheckpoint(afterSlot: 9, paginationToken: "1:10:s"), .start],
            outputCheckpoints: [.start, IndexerCheckpoint(afterSlot: 4, paginationToken: nil)]
        )

        let restored = try JSONDecoder().decode(NoteSyncPosition.self, from: try JSONEncoder().encode(position))

        #expect(restored == position)
        #expect(restored.hashValue == position.hashValue)
    }

    @Test
    func `First reads start each group from the beginning`() {
        #expect(NoteSyncPosition(tags: [[1]], groupCount: 2)
            == NoteSyncPosition(tags: [[1]], transactionCheckpoints: [.start, .start], outputCheckpoints: [.start, .start]))
    }

    @Test(arguments: [
        ([[UInt8]]([[1], [2]]), 1, true), ([[2], [1]], 1, false), ([[1]], 1, false), ([[1], [2]], 2, false),
    ])
    func `Positions match only the same tags in order`(tags: [[UInt8]], groupCount: Int, expected: Bool) {
        let position = NoteSyncPosition(tags: [[1], [2]], groupCount: 1)

        #expect(position.matches(tags, groupCount: groupCount) == expected)
    }
}
