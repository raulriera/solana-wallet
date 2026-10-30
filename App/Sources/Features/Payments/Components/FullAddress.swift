import SwiftUI

/// Shows a whole address that people can select and copy.
struct FullAddress: View {
    /// The address's text, or pasted text that may not be an address.
    let text: String

    var body: some View {
        Text(text)
            .monospaced()
            .speechSpellsOutCharacters()
            .typesettingLanguage(Locale.Language(identifier: "zxx"))
            .textSelection(.enabled)
    }
}
