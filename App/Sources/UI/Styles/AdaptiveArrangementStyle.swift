import SwiftUI

/// Places an arrangement's regions stacked or side by side from the space they have and the space their content uses,
/// and splits them at an active fold.
///
/// Space wider than tall places the regions side by side. Other space stacks them, close together when both fit at
/// the height their content uses, or with the secondary region giving up height.
///
/// A horizontal fold through the middle stacks the regions on either side of it, so on iPhone Duo in a table pose the
/// secondary region sits on the flat half; a vertical one places them side by side. A fold nearer an edge keeps the
/// regions on its larger side.
///
/// When the secondary region has a second view, such as an action under a keypad, that view stays under the
/// secondary region's first view while the regions stack, and moves under the primary region while they sit side by
/// side, so the secondary region keeps the full height. It takes the width of the secondary region's first view.
///
/// The system's `.split` style shows only the primary region in landscape on a closed iPhone Duo, so this style picks
/// the direction itself.
struct AdaptiveArrangementStyle: ArrangementViewStyle {
    /// Lays out the same regions in either direction without replacing their view identities.
    /// - Parameter configuration: The primary and secondary regions supplied by the arrangement.
    /// - Returns: The regions side by side or stacked, around a fold when one is active.
    func makeBody(configuration: Configuration) -> some View {
        AdaptiveArrangement(configuration: configuration)
    }
}

extension ArrangementViewStyle where Self == AdaptiveArrangementStyle {
    /// Side by side in space wider than tall, stacked otherwise, split at an active fold.
    static var adaptive: Self { Self() }
}
