import Testing
import RPC

/// Verifies private-note refusals stay distinguishable.
struct PrivateNoteErrorTests {
    /// Verifies each refusal equals only itself, so callers can tell them apart.
    ///
    /// - Parameters:
    ///   - error: A refusal.
    ///   - other: A different refusal.
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
