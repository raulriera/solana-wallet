import Foundation

/// A reason the keypad left the amount unchanged.
nonisolated enum AmountRejection: Equatable, Sendable {
    /// The key would break the amount's format or limits.
    case key
    /// The amount, converted to the other unit, has more whole digits than the keypad types.
    case conversion

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
