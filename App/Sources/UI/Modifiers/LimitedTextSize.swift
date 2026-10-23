import SwiftUI

extension View {
    /// Stops text and scaled sizes at the largest standard text size; the app doesn't support the accessibility sizes.
    ///
    /// Apply it to each window's root and to each sheet: a sheet doesn't inherit the limit from the window that
    /// presents it.
    /// - Returns: The view with text sizes up to the largest standard size.
    func limitedTextSize() -> some View {
        dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }
}
