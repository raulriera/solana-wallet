import Foundation
import Testing
import Wallet
@testable import widgets

/// Checks that a rejection's explanation never repeats the recovery words, apart from naming one unknown word.
@MainActor
struct RecoveryPhraseRejectionMessageTests {
    /// Public word-list entries that appear nowhere in the explanations' own wording.
    private static let words = ["zebra", "wolf", "yellow", "zoo", "kiwi", "lemon", "mango", "piano", "tiger", "violin",
                                "walnut", "jungle"]

    /// Rejections of the whole phrase explain it without naming any of its words.
    /// - Parameter rejection: Why the phrase can't be used.
    /// - Throws: A test prerequisite error when the rejection has no explanation.
    @Test(arguments: [RecoveryPhrase.ValidationError.invalidWordCount, .invalidChecksum, .invalidEntropy])
    func `A whole-phrase rejection names none of the words`(rejection: RecoveryPhrase.ValidationError) throws {
        let message = String(localized: try #require(rejection.message(in: Self.words.joined(separator: " "))))

        #expect(Self.words.filter { message.contains($0) }.isEmpty)
    }

    /// An unknown word is named on its own, without the words around it.
    /// - Throws: A test prerequisite error when the rejection has no explanation.
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
