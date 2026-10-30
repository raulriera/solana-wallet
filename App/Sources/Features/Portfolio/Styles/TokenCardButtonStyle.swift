import SwiftUI

/// A button style that keeps an overlapping card opaque while it's pressed.
struct TokenCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

extension ButtonStyle where Self == TokenCardButtonStyle {
    static var tokenCard: TokenCardButtonStyle { TokenCardButtonStyle() }
}
