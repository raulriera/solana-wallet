import Testing
@testable import widgets

/// Checks input mutation and cleanup without duplicating the Wallet framework's BIP-39 tests.
@MainActor
struct RecoveryInputTests {
    /// Editing clears the previous inline failure immediately without observing the phrase as a key.
    @Test
    func `Editing recovery clears validation while preserving the exact passphrase`() {
        let input = RecoveryInput(phrase: "public invalid fixture")
        input.passphrase = " TrEzOr "
        #expect(!input.validate())
        #expect(input.validationMessage != nil)

        input.phrase = OnboardingCoordinatorTests.phrase

        #expect(input.validationMessage == nil)
        #expect(input.hasPhrase)
        #expect(input.passphrase == " TrEzOr ")
    }

    /// Leaving a screen resets the model retained by its SwiftUI state storage.
    @Test
    func `Leaving recovery entry clears input validation and reveal state`() {
        let input = RecoveryInput(phrase: "public invalid fixture")
        input.passphrase = " TrEzOr "
        input.showsWords = true
        input.validate()

        input.clear()

        #expect(input.phrase.isEmpty)
        #expect(input.passphrase.isEmpty)
        #expect(!input.hasPhrase)
        #expect(!input.showsWords)
        #expect(input.validationMessage == nil)
    }
}
