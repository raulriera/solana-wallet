import SwiftUI

/// Sizes a sheet to the height of its scrolling content, top bar included.
private struct ContentHeightDetent: ViewModifier {
    @State private var detent = PresentationDetent.medium

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: CGFloat?.self) { geometry in
                guard geometry.contentInsets.top > 0 else { return nil }
                return geometry.contentSize.height + geometry.contentInsets.top
            } action: { _, height in
                if let height { detent = .height(height) }
            }
            .presentationDetents([detent], selection: $detent)
    }
}

extension View {
    /// Sizes the sheet that presents this scrolling content to the content's height, top bar included.
    ///
    /// - Returns: The view with its sheet's detent set to its height.
    func contentHeightDetent() -> some View {
        modifier(ContentHeightDetent())
    }
}
