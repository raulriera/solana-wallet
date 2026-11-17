import Testing
@testable import widgets

@MainActor
struct SendErrorTests {
    @Test(arguments: [
        (SendError.notEnoughSOL, false),
        (.amountTooSmall, false),
        (.preparationFailed, true),
        (.notSent, true),
    ])
    func `Only errors that need a different payment can't be tried again`(error: SendError, canRetry: Bool) {
        #expect(error.canRetry == canRetry)
    }

    @Test(arguments: SendError.allCases)
    func `Every error explains itself`(error: SendError) {
        #expect(error.errorDescription?.isEmpty == false)
        #expect(error.recoverySuggestion?.isEmpty == false)
    }
}
