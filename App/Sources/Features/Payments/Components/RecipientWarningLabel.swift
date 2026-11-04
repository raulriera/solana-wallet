import SwiftUI

/// A label that shows a recipient warning, in the destructive color when it's serious.
struct RecipientWarningLabel: View {
    @Environment(\.palette) private var palette
    let warning: RecipientWarning

    var body: some View {
        Label(warning.message, systemImage: warning.systemImage)
            .foregroundStyle(warning.isSerious ? palette.destructive : palette.secondaryText)
    }
}
