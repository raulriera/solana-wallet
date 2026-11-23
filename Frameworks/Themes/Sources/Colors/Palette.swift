/// The semantic colors for one appearance.
public struct Palette: Sendable, Equatable {
    /// A semantic color role.
    public enum Role: String, CaseIterable, Sendable {
        /// The main content background color.
        case background
        /// The color of content layered on the background.
        case surface
        /// The color of content dividers.
        case separator
        /// The fill of primary buttons, and the color of links and controls without a fill.
        case primary
        /// The color of text and symbols on the primary color.
        case onPrimary
        /// The fill of secondary buttons.
        case secondary
        /// The color of text and symbols on the secondary color.
        case onSecondary
        /// The fill of destructive buttons, and the color of destructive text without a fill.
        case destructive
        /// The color of text and symbols on the destructive color.
        case onDestructive
        /// The outline of buttons.
        case border
        /// The background of sidebars.
        case sidebar
    }

    /// Every color, by role.
    let values: [Role: Color]

    /// Creates a palette with a color for every role.
    ///
    /// - Parameter color: Returns the color for a role.
    public init(_ color: (Role) -> Color) {
        values = Dictionary(uniqueKeysWithValues: Role.allCases.map { ($0, color($0)) })
    }

    /// The color for a role.
    public subscript(role: Role) -> Color {
        // swift-format-ignore: NeverForceUnwrap
        values[role]!
    }

    /// Returns the palette with overrides applied.
    ///
    /// - Parameter overrides: The validated colors to override, by role.
    /// - Returns: The palette, with its own colors for omitted roles.
    func applying(_ overrides: [Role: Color]) -> Palette {
        Palette { overrides[$0] ?? self[$0] }
    }
}
