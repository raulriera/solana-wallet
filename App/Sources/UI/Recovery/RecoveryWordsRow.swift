import SwiftUI

/// Shows one grid row of numbered recovery words.
struct RecoveryWordsRow: View {
    let words: ArraySlice<NumberedWord>

    var body: some View {
        GridRow {
            ForEach(words) { word in
                Text("\(word.position).")
                    .accessibilityHidden(true)
                Text(word.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("\(word.position). \(word.text)")
            }
        }
    }
}
