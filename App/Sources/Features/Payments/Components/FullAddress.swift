import SwiftUI

/// Shows a whole address so people can check every character, and copy it with a touch and hold.
///
/// VoiceOver spells it out, since an address isn't words.
struct FullAddress: View {
    /// The address's text, or pasted text that may not be an address.
    let text: String

    var body: some View {
        Text(text)
            .monospaced()
            .speechSpellsOutCharacters()
            // An address isn't language, so a wrapped line never gets a hyphen that could be read as part of it.
            .typesettingLanguage(Locale.Language(identifier: "zxx"))
            .textSelection(.enabled)
    }
}
