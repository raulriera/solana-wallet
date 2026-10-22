import SwiftUI

/// Explains something to check about a recipient, in red like other warnings.
struct RecipientWarningLabel: View {
    let warning: RecipientWarning

    var body: some View {
        Label(warning.message, systemImage: warning.systemImage)
            .labelStyle(.warning)
    }
}
