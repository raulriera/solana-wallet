import SwiftUI

/// One accessible theme choice with an independent SwiftUI update boundary.
struct ThemeChoiceRow: View {
    let name: String
    let isSelected: Bool
    let palette: RenderedPalette
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack {
                Text(name).foregroundStyle(palette.primaryText)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark").foregroundStyle(palette.accent).accessibilityHidden(true)
                }
            }
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .listRowBackground(palette.surface)
        .listRowSeparatorTint(palette.separator)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
