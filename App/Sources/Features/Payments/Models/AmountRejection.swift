import Foundation

/// Why the keypad left the amount as it was.
nonisolated enum AmountRejection: Equatable, Sendable {
    /// The key would break the amount's format or limits, such as a second separator or a digit past the unit's.
    case key
    /// The amount, converted to the other unit, has more whole digits than the keypad types.
    case conversion

    /// Tells VoiceOver why the amount didn't change.
    var message: LocalizedStringResource {
        switch self {
        case .key:
            LocalizedStringResource("Amount unchanged",
                                    comment: "VoiceOver announcement when a keypad key would make the amount invalid.")
        case .conversion:
            LocalizedStringResource("Too large to convert",
                                    comment: "VoiceOver announcement when the amount can't be shown in the other unit.")
        }
    }
}
