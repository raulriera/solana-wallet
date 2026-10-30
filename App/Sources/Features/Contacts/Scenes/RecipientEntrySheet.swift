import SwiftUI

/// Presents a recipient sheet in its own navigation container.
struct RecipientEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    let entry: RecipientEntryModel
    let lists: ContactLists

    var body: some View {
        NavigationStack {
            RecipientEntryScreen(entry: entry, lists: lists)
                .onChange(of: entry.confirmation) { dismiss() }
                .cancellationAction()
        }
        .limitedTextSize()
    }
}
