import SwiftUI

/// A button style for a list choice that shows a checkmark while it's selected.
struct ChoiceButtonStyle: PrimitiveButtonStyle {
    /// The position of a choice's checkmark.
    enum CheckmarkPlacement {
        /// Before the name, keeping its space while hidden.
        case leading
        case trailing
    }

    @Environment(\.palette) private var palette
    private let isSelected: Bool
    private let placement: CheckmarkPlacement

    /// Creates a choice style.
    ///
    /// - Parameters:
    ///   - isSelected: Whether the choice is selected.
    ///   - placement: Where the checkmark goes.
    fileprivate init(isSelected: Bool, placement: CheckmarkPlacement) {
        self.isSelected = isSelected
        self.placement = placement
    }

    func makeBody(configuration: Configuration) -> some View {
        Button(role: configuration.role, action: configuration.trigger) {
            HStack {
                if placement == .leading {
                    Label {
                        configuration.label
                    } icon: {
                        Image(systemName: "checkmark")
                            .foregroundStyle(palette.primary)
                            .opacity(isSelected ? 1 : 0)
                            .accessibilityHidden(true)
                    }
                } else {
                    configuration.label
                }
                Spacer()
                if placement == .trailing, isSelected {
                    Image(systemName: "checkmark").foregroundStyle(palette.primary).accessibilityHidden(true)
                }
            }
            .foregroundStyle(palette.text)
            .contentShape(.rect)
        }
        .buttonStyle(.automatic)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

extension PrimitiveButtonStyle where Self == ChoiceButtonStyle {
    /// Returns a style for a list choice that shows a checkmark while it's selected.
    ///
    /// - Parameters:
    ///   - isSelected: Whether the choice is selected.
    ///   - placement: Where the checkmark goes.
    /// - Returns: The choice style.
    static func choice(isSelected: Bool, placement: ChoiceButtonStyle.CheckmarkPlacement = .trailing) -> Self {
        Self(isSelected: isSelected, placement: placement)
    }
}
