import Algorithms
import SwiftUI
import Wallet

/// Shows numbered recovery words in reading order in two columns.
struct RecoveryWords: View {
    @Environment(\.palette) private var palette
    @Environment(\.canDisplayRecovery) private var canDisplayRecovery
    let phrase: RecoveryPhrase

    var body: some View {
        let visibleWords = canDisplayRecovery ? phrase.words : Array(repeating: String(localized: "Hidden"), count: phrase.words.count)
        let numberedWords = zip(1..., visibleWords).map { (position: $0.0, word: $0.1) }
        let rows = numberedWords.chunks(ofCount: 2)
        Grid(alignment: .trailingFirstTextBaseline) {
            ForEach(rows, id: \.startIndex) { row in
                GridRow {
                    ForEach(row, id: \.position) { word in
                        Text("\(word.position).")
                            .accessibilityHidden(true)
                        Text(word.word)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityLabel("\(word.position). \(word.word)")
                    }
                }
            }
        }
        .foregroundStyle(palette.text)
        .privacySensitive()
        .transaction { transaction in transaction.animation = nil }
    }
}
