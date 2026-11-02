import Testing
import RPC

struct PrivateNoteErrorTests {
    @Test(arguments: [
        (PrivateNoteError.invalidTag, PrivateNoteError.invalidNullifier),
        (.invalidNullifier, .mismatchedPosition),
        (.mismatchedPosition, .invalidTag),
    ])
    func `Refusals are distinct`(error: PrivateNoteError, other: PrivateNoteError) {
        #expect(error == error)
        #expect(error != other)
    }
}
