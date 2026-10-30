import SwiftUI

/// A system Paste button that pastes text.
struct PasteTextButton: View {
    @Environment(\.palette) private var palette
    let paste: (String) -> Void

    var body: some View {
        PasteButton(payloadType: String.self) { paste($0.first ?? "") }
            .buttonBorderShape(.capsule)
            .tint(palette.accent)
    }
}
