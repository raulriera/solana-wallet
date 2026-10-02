import SwiftUI
import Wallet

/// Presents numbered recovery words in reading order across two flexible columns.
struct RecoveryWords: View {
    @Environment(\.palette) private var palette
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isSceneCaptured) private var isSceneCaptured
    let phrase: RecoveryPhrase

    private var revealsWords: Bool { scenePhase == .active && !isSceneCaptured }

    var body: some View {
        let visibleWords = revealsWords ? phrase.words : Array(repeating: String(localized: "Hidden"), count: phrase.words.count)
        let numberedWords = zip(1..., visibleWords).map { (position: $0.0, word: $0.1) }
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 2)) {
            // Positions preserve backup order across resizing and repeated words.
            ForEach(numberedWords, id: \.position) { word in
                Text("\(word.position). \(word.word)")
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
        }
        .foregroundStyle(palette.primaryText)
        .privacySensitive()
        .transaction { transaction in transaction.animation = nil }
    }
}
