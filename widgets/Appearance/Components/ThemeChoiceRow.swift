import SwiftUI

/// One accessible theme choice with an independent SwiftUI update boundary.
struct ThemeChoiceRow: View {
    let name: String
    let isSelected: Bool
    let primaryText: Color
    let accent: Color
    let surface: Color
    let separator: Color
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack {
                Text(name).foregroundStyle(primaryText)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark").foregroundStyle(accent).accessibilityHidden(true)
                }
            }
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .listRowBackground(surface)
        .listRowSeparatorTint(separator)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
