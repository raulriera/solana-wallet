import SwiftUI

extension View {
    /// Limits text and scaled sizes to the largest standard text size.
    ///
    /// - Returns: The view with text sizes up to the largest standard size.
    func limitedTextSize() -> some View {
        dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }
}
