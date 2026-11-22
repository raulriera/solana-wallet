import SwiftUI

nonisolated extension EnvironmentValues {
    @Entry var palette = RenderedPalette(OriginalAppearance.palette)
}
