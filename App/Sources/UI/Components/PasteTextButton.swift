import SwiftUI

/// Pastes text with the system Paste button, placed on the trailing side of the field it fills.
///
/// The system button pastes without asking for permission, and turns off when there's nothing to paste.
/// Only its shape and tint can change.
struct PasteTextButton: View {
    @Environment(\.palette) private var palette
    /// Receives the pasted text.
    let paste: (String) -> Void

    var body: some View {
        PasteButton(payloadType: String.self) { paste($0.first ?? "") }
            .buttonBorderShape(.capsule)
            .tint(palette.accent)
    }
}
