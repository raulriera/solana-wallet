import SwiftUI

/// Keeps the removal confirmation anchored to the custom theme's action menu.
struct ThemePackRow: View {
    let entry: ThemeEntry
    let palette: RenderedPalette
    let export: () -> Void
    let remove: (ThemeEntry) -> Void
    @State private var removal: ThemeEntry?

    var body: some View {
        HStack {
            Text(entry.name).foregroundStyle(palette.primaryText)
            Spacer()
            Menu {
                Button("Export…", systemImage: "square.and.arrow.up", action: export)
                Button("Remove…", systemImage: "trash", role: .destructive) { removal = entry }
            } label: {
                Label("Actions for \(entry.name)", systemImage: "ellipsis.circle")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(palette.accent)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .confirmationDialog("Remove Theme?", item: $removal) { approved in
                Button("Remove", role: .destructive) { remove(approved) }
            } message: { approved in
                Text("Remove \(approved.name)? The app default returns to Original if needed. Wallets using this theme return to the app default.")
            }
        }
    }
}
