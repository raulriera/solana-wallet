import SwiftUI

/// Presents a recipient sheet in its own navigation container.
///
/// The sheet closes itself on Cancel and once the person confirms.
struct RecipientEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    let entry: RecipientEntryModel

    var body: some View {
        NavigationStack {
            RecipientEntryScreen(entry: entry)
                .onChange(of: entry.confirmation) { dismiss() }
                .cancellationAction()
        }
        .limitedTextSize()
    }
}
