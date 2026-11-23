import SwiftUI

/// A button style that shows a checkmark on a button marked `checked(_:)`, and leaves other buttons plain.
///
/// A choice's label is its name, and any views after the first are its description.
struct ChoiceButtonStyle: PrimitiveButtonStyle {
    /// The position of a choice's checkmark.
    enum CheckmarkPlacement {
        /// Before the name, keeping its space while hidden.
        case leading
        case trailing
    }

    @Environment(\.palette) private var palette
    @Environment(\.isChecked) private var isChecked
    private let placement: CheckmarkPlacement
    private let descriptionSpacing: CGFloat?

    /// Creates a choice style.
    ///
    /// - Parameters:
    ///   - placement: Where the checkmark goes.
    ///   - descriptionSpacing: The distance between the name and the description, or `nil` for the default.
    fileprivate init(placement: CheckmarkPlacement, descriptionSpacing: CGFloat?) {
        self.placement = placement
        self.descriptionSpacing = descriptionSpacing
    }

    func makeBody(configuration: Configuration) -> some View {
        if let isChecked {
            let label = LabeledContent {
            } label: {
                configuration.label
            }
            .labeledContentStyle(.subtitled(spacing: descriptionSpacing))
            Button(role: configuration.role, action: configuration.trigger) {
                HStack {
                    if placement == .leading {
                        Label {
                            label
                        } icon: {
                            Image(systemName: "checkmark")
                                .foregroundStyle(palette.primary)
                                .opacity(isChecked ? 1 : 0)
                                .accessibilityHidden(true)
                        }
                    } else {
                        label
                    }
                    Spacer()
                    if placement == .trailing, isChecked {
                        Image(systemName: "checkmark").foregroundStyle(palette.primary).accessibilityHidden(true)
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.automatic)
            .tint(.primary)
            .accessibilityAddTraits(isChecked ? [.isSelected] : [])
        } else {
            Button(configuration)
                .buttonStyle(.automatic)
        }
    }
}

extension PrimitiveButtonStyle where Self == ChoiceButtonStyle {
    /// Returns a style that shows a checkmark on a button marked `checked(_:)`.
    ///
    /// - Parameters:
    ///   - placement: Where the checkmark goes.
    ///   - descriptionSpacing: The distance between the name and the description, or `nil` for the default.
    /// - Returns: The choice style.
    static func choice(placement: ChoiceButtonStyle.CheckmarkPlacement, descriptionSpacing: CGFloat?) -> Self {
        Self(placement: placement, descriptionSpacing: descriptionSpacing)
    }
}

extension View {
    /// Makes a button a choice in a form that uses the choice style.
    ///
    /// - Parameter isChecked: Whether the choice shows its checkmark.
    /// - Returns: A view that is a choice with the given state.
    func checked(_ isChecked: Bool) -> some View {
        environment(\.isChecked, isChecked)
    }
}
