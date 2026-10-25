import Testing
@testable import widgets

/// Checks which payment errors can be tried again.
@MainActor
struct SendErrorTests {
    /// A simulation that ran out of SOL fails the same way again; every other error can be tried again.
    /// - Parameters:
    ///   - error: The payment error.
    ///   - canRetry: Whether trying again can help.
    @Test(arguments: [
        (SendError.notEnoughSOL, false),
        (.preparationFailed, true),
        (.notSent, true),
        (.watchStopped, true),
    ])
    func `Only running out of SOL can't be tried again`(error: SendError, canRetry: Bool) {
        #expect(error.canRetry == canRetry)
    }

    /// Every error has a title and a message for its alert.
    /// - Parameter error: The payment error.
    @Test(arguments: SendError.allCases)
    func `Every error explains itself`(error: SendError) {
        #expect(error.errorDescription?.isEmpty == false)
        #expect(error.recoverySuggestion?.isEmpty == false)
    }
}
