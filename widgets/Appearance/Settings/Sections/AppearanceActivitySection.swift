import SwiftUI

/// Displays the active operation without observing unrelated preference or catalog state.
struct AppearanceActivitySection: View {
    let activity: String
    let palette: RenderedPalette

    var body: some View {
        Section {
            HStack {
                ProgressView()
                Text(activity).foregroundStyle(palette.secondaryText)
            }
        }
        .listRowBackground(palette.surface)
    }
}
