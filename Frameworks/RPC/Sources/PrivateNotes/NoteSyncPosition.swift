import CryptoKit

/// The position where a read of shielded transactions by view tag stopped.
public struct NoteSyncPosition: Sendable, Hashable, Codable {
    let tagDigest: [UInt8]
    /// The checkpoint of each tag group's confidential-transaction stream.
    let transactionCheckpoints: [IndexerCheckpoint]
    /// The checkpoint of each tag group's encrypted-output stream.
    let outputCheckpoints: [IndexerCheckpoint]

    /// Creates a position for view tags from each tag group's checkpoints.
    ///
    /// - Parameters:
    ///   - tags: The view tags, in request order.
    ///   - transactionCheckpoints: The confidential-transaction checkpoints, one per tag group.
    ///   - outputCheckpoints: The encrypted-output checkpoints, one per tag group.
    init(tags: [[UInt8]], transactionCheckpoints: [IndexerCheckpoint], outputCheckpoints: [IndexerCheckpoint]) {
        tagDigest = Self.digest(of: tags)
        self.transactionCheckpoints = transactionCheckpoints
        self.outputCheckpoints = outputCheckpoints
    }

    /// Creates the position before the first row.
    ///
    /// - Parameters:
    ///   - tags: The view tags, in request order.
    ///   - groupCount: The number of tag groups that the read requests.
    init(tags: [[UInt8]], groupCount: Int) {
        self.init(tags: tags, transactionCheckpoints: Array(repeating: .start, count: groupCount),
                  outputCheckpoints: Array(repeating: .start, count: groupCount))
    }

    /// Returns whether the position came from a read of these view tags, in this order and number of groups.
    ///
    /// - Parameters:
    ///   - tags: The view tags of the new read.
    ///   - groupCount: The number of tag groups of the new read.
    /// - Returns: `true` when the digest and both streams' group counts match.
    func matches(_ tags: [[UInt8]], groupCount: Int) -> Bool {
        tagDigest == Self.digest(of: tags) && transactionCheckpoints.count == groupCount
            && outputCheckpoints.count == groupCount
    }

    /// Returns the SHA-256 digest of view tags concatenated in order.
    ///
    /// - Parameter tags: The view tags.
    /// - Returns: The 32-byte digest.
    private static func digest(of tags: [[UInt8]]) -> [UInt8] {
        Array(SHA256.hash(data: tags.flatMap(\.self)))
    }
}
