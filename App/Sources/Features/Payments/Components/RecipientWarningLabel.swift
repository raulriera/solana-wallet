import SwiftUI

/// Explains something to check about a recipient: in red, like other warnings, when the payment could go somewhere
/// unintended, and in gray otherwise.
struct RecipientWarningLabel: View {
    @Environment(\.palette) private var palette
    let warning: RecipientWarning

    var body: some View {
        Label(warning.message, systemImage: warning.systemImage)
            .foregroundStyle(warning.isSerious ? .red : palette.secondaryText)
    }
}
