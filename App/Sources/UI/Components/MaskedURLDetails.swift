import SwiftUI

/// A form that shows a URL with the parts that can contain a key hidden, above its actions, and closes once the URL
/// leaves its list.
struct MaskedURLDetails<Actions: View>: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    let url: URL
    let title: LocalizedStringResource
    let footer: LocalizedStringResource
    /// Whether the URL is still in its list.
    let isListed: Bool
    @ViewBuilder let actions: Actions

    var body: some View {
        Form {
            Section {
                Text(url, format: .maskedURL)
                    .foregroundStyle(palette.text)
                    .accessibilityLabel(Text(url, format: .spokenMaskedURL))
            } header: {
                Text("URL")
            } footer: {
                Text(footer)
                    .foregroundStyle(palette.secondaryText)
            }

            Section {
                actions
            }
        }
        .navigationTitle(Text(title))
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: isListed) { dismiss() }
    }
}
