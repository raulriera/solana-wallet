import CryptoKit

/// The position where a read of shielded transactions by view tag stopped.
public struct NoteSyncPosition: Sendable, Hashable, Codable {
    let tagDigest: [UInt8]
    /// The cursor of each tag group's confidential-transaction stream, or `nil` for the start.
    let transactionCursors: [String?]
    /// The cursor of each tag group's encrypted-output stream, or `nil` for the start.
    let outputCursors: [String?]

    /// Creates a position for view tags from each tag group's cursors.
    ///
    /// - Parameters:
    ///   - tags: The view tags, in request order.
    ///   - transactionCursors: The confidential-transaction cursors, one per tag group.
    ///   - outputCursors: The encrypted-output cursors, one per tag group.
    init(tags: [[UInt8]], transactionCursors: [String?], outputCursors: [String?]) {
        tagDigest = Self.digest(of: tags)
        self.transactionCursors = transactionCursors
        self.outputCursors = outputCursors
    }

    /// Creates the position before the first row.
    ///
    /// - Parameters:
    ///   - tags: The view tags, in request order.
    ///   - groupCount: The number of tag groups that the read requests.
    init(tags: [[UInt8]], groupCount: Int) {
        self.init(tags: tags, transactionCursors: Array(repeating: nil, count: groupCount),
                  outputCursors: Array(repeating: nil, count: groupCount))
    }

    /// Returns whether the position came from a read of these view tags, in this order and number of groups.
    ///
    /// - Parameters:
    ///   - tags: The view tags of the new read.
    ///   - groupCount: The number of tag groups of the new read.
    /// - Returns: `true` when the digest and both streams' group counts match.
    func matches(_ tags: [[UInt8]], groupCount: Int) -> Bool {
        tagDigest == Self.digest(of: tags) && transactionCursors.count == groupCount && outputCursors.count == groupCount
    }

    /// Returns the SHA-256 digest of view tags concatenated in order.
    ///
    /// - Parameter tags: The view tags.
    /// - Returns: The 32-byte digest.
    private static func digest(of tags: [[UInt8]]) -> [UInt8] {
        Array(SHA256.hash(data: tags.flatMap(\.self)))
    }
}
