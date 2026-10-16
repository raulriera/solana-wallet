import Foundation
import Testing
@testable import RPC

/// Verifies that sync positions can be stored and restored.
struct NoteSyncPositionTests {
    /// Verifies a position survives encoding and decoding, including groups without a cursor.
    ///
    /// - Throws: An encoding or decoding error.
    @Test
    func `Positions survive storage`() throws {
        let position = NoteSyncPosition(tags: [[1], [2]], transactionCursors: ["AQ==", nil], outputCursors: [nil, "Ag=="])

        let restored = try JSONDecoder().decode(NoteSyncPosition.self, from: try JSONEncoder().encode(position))

        #expect(restored == position)
        #expect(restored.hashValue == position.hashValue)
    }

    /// Verifies a first read starts every group of both streams without a cursor.
    @Test
    func `First reads start each group from the beginning`() {
        #expect(NoteSyncPosition(tags: [[1]], groupCount: 2)
            == NoteSyncPosition(tags: [[1]], transactionCursors: [nil, nil], outputCursors: [nil, nil]))
    }

    /// Verifies a position matches only the same tags, in the same order and group count.
    ///
    /// - Parameters:
    ///   - tags: The tags of the new read.
    ///   - groupCount: The group count of the new read.
    ///   - expected: Whether the position matches.
    @Test(arguments: [
        ([[UInt8]]([[1], [2]]), 1, true), ([[2], [1]], 1, false), ([[1]], 1, false), ([[1], [2]], 2, false),
    ])
    func `Positions match only the same tags in order`(tags: [[UInt8]], groupCount: Int, expected: Bool) {
        let position = NoteSyncPosition(tags: [[1], [2]], groupCount: 1)

        #expect(position.matches(tags, groupCount: groupCount) == expected)
    }
}
