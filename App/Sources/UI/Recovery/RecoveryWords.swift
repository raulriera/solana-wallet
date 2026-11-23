import Algorithms
import SwiftUI
import Wallet

/// Shows numbered recovery words in reading order in two columns.
struct RecoveryWords: View {
    @Environment(\.canDisplayRecovery) private var canDisplayRecovery
    let phrase: RecoveryPhrase

    var body: some View {
        let visibleWords = canDisplayRecovery ? phrase.words : Array(repeating: String(localized: "Hidden"), count: phrase.words.count)
        let numberedWords = zip(1..., visibleWords).map { NumberedWord(position: $0, text: $1) }
        Grid(alignment: .trailingFirstTextBaseline) {
            ForEach(numberedWords.chunks(ofCount: 2), id: \.startIndex) { words in
                RecoveryWordsRow(words: words)
            }
        }
        .privacySensitive()
        .transaction { transaction in transaction.animation = nil }
    }
}
