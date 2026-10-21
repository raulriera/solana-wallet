import Testing
import Wallet

/// Verifies that one-time account errors contain no secret or rejected input.
struct OneTimeAccountErrorTests {
    /// Verifies that each error is only its case, with no payload to print or reflect.
    ///
    /// - Parameters:
    ///   - error: A one-time account error.
    ///   - name: The error's case name.
    @Test(arguments: [
        (OneTimeAccountError.invalidCodeRoot, "invalidCodeRoot"), (.invalidIndex, "invalidIndex"),
        (.invalidSecret, "invalidSecret"),
    ])
    func `One-time account errors carry no payload`(error: OneTimeAccountError, name: String) {
        #expect(String(describing: error) == name)
        #expect(Mirror(reflecting: error).children.isEmpty)
    }
}
