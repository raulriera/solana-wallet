import Testing
import Wallet

/// Verifies that private-balance errors contain no recovery material or rejected input.
struct PrivateBalanceErrorTests {
    /// Verifies that each error is only its case, with no payload to print or reflect.
    ///
    /// - Parameters:
    ///   - error: A private-balance error.
    ///   - name: The error's case name.
    @Test(arguments: [(PrivateBalanceError.unsupportedPath, "unsupportedPath"), (.accountMismatch, "accountMismatch")])
    func `Private-balance errors carry no payload`(error: PrivateBalanceError, name: String) {
        #expect(String(describing: error) == name)
        #expect(Mirror(reflecting: error).children.isEmpty)
    }
}
