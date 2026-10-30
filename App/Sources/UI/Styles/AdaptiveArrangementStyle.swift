import SwiftUI

/// An arrangement style that places the regions side by side or stacked from the space they have, and splits
/// them at an active fold.
struct AdaptiveArrangementStyle: ArrangementViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        AdaptiveArrangement(configuration: configuration)
    }
}

extension ArrangementViewStyle where Self == AdaptiveArrangementStyle {
    /// Regions side by side in wide space, stacked otherwise, and split at an active fold.
    static var adaptive: Self { Self() }
}
