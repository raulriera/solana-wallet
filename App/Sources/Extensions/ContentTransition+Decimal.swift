import SwiftUI

extension ContentTransition {
    /// Creates a content transition for text that shows a decimal number.
    ///
    /// - Parameter value: The number the text shows.
    /// - Returns: A numeric text transition for the number.
    static func numericText(value: Decimal) -> ContentTransition {
        .numericText(value: NSDecimalNumber(decimal: value).doubleValue)
    }
}
