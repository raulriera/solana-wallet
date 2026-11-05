import SwiftUI

/// A themed form style that turns the buttons marked `checked(_:)` into choices.
struct ChoiceFormStyle: FormStyle {
    private let checkmark: ChoiceButtonStyle.CheckmarkPlacement
    private let descriptionSpacing: CGFloat?

    /// Creates a choice form style.
    ///
    /// - Parameters:
    ///   - checkmark: Where each choice's checkmark goes.
    ///   - descriptionSpacing: The distance between a choice's name and description, or `nil` for the default.
    fileprivate init(checkmark: ChoiceButtonStyle.CheckmarkPlacement, descriptionSpacing: CGFloat?) {
        self.checkmark = checkmark
        self.descriptionSpacing = descriptionSpacing
    }

    func makeBody(configuration: Configuration) -> some View {
        Form {
            configuration.content
                .buttonStyle(.choice(placement: checkmark, descriptionSpacing: descriptionSpacing))
        }
        .formStyle(.themed)
    }
}

extension FormStyle where Self == ChoiceFormStyle {
    /// A themed style for a form of choices with trailing checkmarks.
    static var choices: Self { .choices() }

    /// Returns a themed style for a form of choices.
    ///
    /// - Parameters:
    ///   - checkmark: Where each choice's checkmark goes.
    ///   - descriptionSpacing: The distance between a choice's name and description, or `nil` for the default.
    /// - Returns: The choice form style.
    static func choices(checkmark: ChoiceButtonStyle.CheckmarkPlacement = .trailing,
                        descriptionSpacing: CGFloat? = nil) -> Self {
        Self(checkmark: checkmark, descriptionSpacing: descriptionSpacing)
    }
}
