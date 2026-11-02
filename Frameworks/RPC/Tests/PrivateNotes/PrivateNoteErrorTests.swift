import RPC
import Testing

struct PrivateNoteErrorTests {
    @Test(arguments: [
        (PrivateNoteError.invalidTag, PrivateNoteError.invalidNullifier),
        (.invalidNullifier, .mismatchedPosition),
        (.mismatchedPosition, .invalidLeaf),
        (.invalidLeaf, .invalidTree),
        (.invalidTree, .invalidTag),
    ])
    func `Refusals are distinct`(error: PrivateNoteError, other: PrivateNoteError) {
        #expect(error == error)
        #expect(error != other)
    }
}
