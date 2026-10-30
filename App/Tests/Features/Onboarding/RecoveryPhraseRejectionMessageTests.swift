import Foundation
import Testing
import Wallet
@testable import widgets

@MainActor
struct RecoveryPhraseRejectionMessageTests {
    private static let words = ["zebra", "wolf", "yellow", "zoo", "kiwi", "lemon", "mango", "piano", "tiger", "violin",
                                "walnut", "jungle"]

    @Test(arguments: [RecoveryPhrase.ValidationError.invalidWordCount, .invalidChecksum, .invalidEntropy])
    func `A whole-phrase rejection names none of the words`(rejection: RecoveryPhrase.ValidationError) throws {
        let message = String(localized: try #require(rejection.message(in: Self.words.joined(separator: " "))))

        #expect(Self.words.filter { message.contains($0) }.isEmpty)
    }

    @Test
    func `An unknown word is named without the rest of the phrase`() throws {
        var words = Self.words
        words[4] = "notaword"
        let rejection = RecoveryPhrase.ValidationError.unknownWord(position: 4)

        let message = String(localized: try #require(rejection.message(in: words.joined(separator: " "))))

        #expect(message.contains("notaword"))
        #expect(words.filter { $0 != "notaword" && message.contains($0) }.isEmpty)
    }
}
