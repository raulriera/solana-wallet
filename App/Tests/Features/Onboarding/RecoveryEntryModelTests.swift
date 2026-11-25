import Testing
import Wallet
@testable import widgets

@MainActor
struct RecoveryEntryModelTests {
    @Test
    func `A repeated rejection counts again`() {
        let input = entry("public invalid fixture")

        input.validate()
        input.validate()

        #expect(input.rejection == .invalidWordCount)
        #expect(input.rejectionCount == 2)
    }

    @Test
    func `Valid recovery words pass without a rejection`() {
        let input = entry(PublicWallet.words)

        #expect(input.validate())
        #expect(input.rejection == nil)
        #expect(input.rejectionCount == 0)
    }

    @Test
    func `Editing recovery clears validation while preserving the exact passphrase`() {
        let input = entry("public invalid fixture")
        input.passphrase = " TrEzOr "
        #expect(!input.validate())
        #expect(input.rejection == .invalidWordCount)

        input.phrase = PublicWallet.words

        #expect(input.rejection == nil)
        #expect(input.hasPhrase)
        #expect(input.passphrase == " TrEzOr ")
    }

    @Test
    func `Writing back the same words keeps the last check`() throws {
        let input = entry("public invalid fixture")
        input.validate()
        let rejection = try #require(input.rejection)

        input.phrase = "public invalid fixture"

        #expect(input.rejection == rejection)
    }

    @Test
    func `Leaving recovery entry clears input validation and reveal state`() {
        let input = entry("public invalid fixture")
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
        #expect(input.rejection == nil)
    }

    private func entry(_ phrase: String) -> RecoveryEntryModel {
        let input = RecoveryEntryModel()
        input.phrase = phrase
        return input
    }
}
