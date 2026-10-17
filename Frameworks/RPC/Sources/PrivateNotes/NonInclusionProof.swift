/// A nullifier's non-inclusion proof in its tree's indexed nullifier tree, as an indexer reads it.
///
/// The proof shows the low element, the largest nullifier below this one, whose next value is above it, at its
/// position under the root. Values are 32 big-endian bytes, the field elements that the prover reads.
public struct NonInclusionProof: Sendable, Equatable {
    /// The nullifier tree's height, the number of siblings in a path.
    public static let height = 40

    /// The nullifier that the tree doesn't hold.
    public let nullifier: [UInt8]
    /// The low element's value.
    public let lowElement: [UInt8]
    /// The low element's position in the tree.
    public let lowElementIndex: UInt64
    /// The low element's next value, above the nullifier.
    public let highElement: [UInt8]
    /// The low element's siblings, leaf level first.
    public let path: [[UInt8]]
    /// The root that the path leads to.
    public let root: [UInt8]
    /// The root's position in the tree's on-chain root history.
    public let rootIndex: UInt16

    /// Creates a proof after checking its lengths.
    ///
    /// - Parameters:
    ///   - nullifier: The 32-byte nullifier.
    ///   - lowElement: The low element's 32-byte value.
    ///   - lowElementIndex: The low element's position.
    ///   - highElement: The low element's 32-byte next value.
    ///   - path: The 40 siblings of 32 bytes, leaf level first.
    ///   - root: The 32-byte root.
    ///   - rootIndex: The root's position in its history.
    /// - Throws: ``PrivateNoteError/invalidProof`` if a value isn't 32 bytes or the path doesn't have 40 siblings.
    public init(nullifier: [UInt8], lowElement: [UInt8], lowElementIndex: UInt64, highElement: [UInt8], path: [[UInt8]],
                root: [UInt8], rootIndex: UInt16) throws {
        guard path.count == Self.height, ([nullifier, lowElement, highElement, root] + path).allSatisfy({ $0.count == 32 })
        else { throw PrivateNoteError.invalidProof }
        self.nullifier = nullifier
        self.lowElement = lowElement
        self.lowElementIndex = lowElementIndex
        self.highElement = highElement
        self.path = path
        self.root = root
        self.rootIndex = rootIndex
    }
}
