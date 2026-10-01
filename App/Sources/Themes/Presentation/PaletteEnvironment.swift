import SwiftUI

extension EnvironmentValues {
    /// The owning window's resolved colors, with the original appearance as a fallback.
    @Entry var palette = RenderedPalette(OriginalAppearance.palette)
}
