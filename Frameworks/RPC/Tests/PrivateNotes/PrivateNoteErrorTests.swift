import Testing
import RPC

struct PrivateNoteErrorTests {
    @Test(arguments: [
        (PrivateNoteError.invalidTag, PrivateNoteError.invalidNullifier),
        (.invalidNullifier, .mismatchedPosition),
        (.mismatchedPosition, .invalidLeaf),
        (.invalidLeaf, .invalidTree),
        (.invalidTree, .tooManyLeaves),
        (.tooManyLeaves, .invalidProof),
        (.invalidProof, .invalidTag),
    ])
    func `Refusals are distinct`(error: PrivateNoteError, other: PrivateNoteError) {
        #expect(error == error)
        #expect(error != other)
    }
}
