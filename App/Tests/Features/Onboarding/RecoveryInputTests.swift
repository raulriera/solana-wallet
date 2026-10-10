import Testing
@testable import widgets

/// Checks input mutation and cleanup without duplicating the Wallet framework's BIP-39 tests.
@MainActor
struct RecoveryInputTests {
    /// Unsupported lengths explain that words may be missing or extra, including counts above twelve.
    /// - Parameter count: An unsupported number of public fixture words.
    @Test(arguments: [11, 13, 25])
    func `Unsupported recovery lengths ask to check for missing or extra words`(count: Int) {
        let input = RecoveryInput(phrase: Array(repeating: "abandon", count: count).joined(separator: " "))

        #expect(!input.validate())
        #expect(input.validationMessage == "Check for missing or extra words.")
    }

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

    /// Switching between the hidden and shown word fields writes the same words back, which isn't an edit.
    @Test
    func `Writing back the same words keeps the last check`() throws {
        let input = RecoveryInput(phrase: "public invalid fixture")
        input.validate()
        let message = try #require(input.validationMessage)

        input.phrase = "public invalid fixture"

        #expect(input.validationMessage == message)
    }

    /// Leaving a screen resets the model retained by its SwiftUI state storage.
    @Test
    func `Leaving recovery entry clears input validation and reveal state`() {
        let input = RecoveryInput(phrase: "public invalid fixture")
        input.passphrase = " TrEzOr "
        input.showsWords = true
        input.showsPassphrase = true
        input.validate()

        input.clear()

        #expect(input.phrase.isEmpty)
        #expect(input.passphrase.isEmpty)
        #expect(!input.hasPhrase)
        #expect(!input.showsWords)
        #expect(!input.showsPassphrase)
        #expect(input.validationMessage == nil)
    }
}
