import SwiftUI
import Wallet

/// Presents numbered recovery words in reading order across two flexible columns.
///
/// Numbers trail-align in their own grid columns so every word in a column starts at the same edge.
struct RecoveryWords: View {
    @Environment(\.palette) private var palette
    @Environment(\.canDisplayRecovery) private var canDisplayRecovery
    let phrase: RecoveryPhrase

    var body: some View {
        let visibleWords = canDisplayRecovery ? phrase.words : Array(repeating: String(localized: "Hidden"), count: phrase.words.count)
        let numberedWords = zip(1..., visibleWords).map { (position: $0.0, word: $0.1) }
        let rows = stride(from: 0, to: numberedWords.count, by: 2).map { numberedWords[$0..<min($0 + 2, numberedWords.count)] }
        Grid(alignment: .trailingFirstTextBaseline) {
            // Positions preserve backup order across resizing and repeated words.
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
        .foregroundStyle(palette.primaryText)
        .privacySensitive()
        .transaction { transaction in transaction.animation = nil }
    }
}
