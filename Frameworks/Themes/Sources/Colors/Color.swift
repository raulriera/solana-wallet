/// A symbolic iOS color or an opaque sRGB color.
public enum Color: Sendable, Equatable {
    case system(System)
    case srgb(red: UInt8, green: UInt8, blue: UInt8)

    /// Supported semantic and adaptable iOS color names.
    public enum System: String, CaseIterable, Sendable {
        case label, secondaryLabel, tertiaryLabel, quaternaryLabel
        case systemFill, secondarySystemFill, tertiarySystemFill, quaternarySystemFill
        case placeholderText, tintColor
        case systemBackground, secondarySystemBackground, tertiarySystemBackground
        case systemGroupedBackground, secondarySystemGroupedBackground, tertiarySystemGroupedBackground
        case separator, opaqueSeparator, link
        case systemBlue, systemBrown, systemCyan, systemGreen, systemIndigo, systemMint
        case systemOrange, systemPink, systemPurple, systemRed, systemTeal, systemYellow
        case systemGray, systemGray2, systemGray3, systemGray4, systemGray5, systemGray6
        case black, white, clear
    }
}
