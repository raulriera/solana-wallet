import SwiftUI

/// Adds a trailing swipe action that asks to delete a row's item.
private struct SwipeDelete<Item>: ViewModifier {
    /// The item waiting for confirmation of its deletion.
    @Binding var removal: Item?
    /// The row's item, or `nil` for a row that can't be deleted.
    let item: Item?

    func body(content: Content) -> some View {
        content
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if let item {
                    SwipeDeleteButton(removal: $removal, item: item)
                }
            }
    }
}

extension View {
    /// Adds a trailing swipe action that asks to delete a row's item.
    ///
    /// - Parameters:
    ///   - item: The row's item, or `nil` for a row that can't be deleted.
    ///   - removal: The item waiting for confirmation of its deletion.
    /// - Returns: The row with its swipe action.
    func swipeDelete<Item>(_ item: Item?, removal: Binding<Item?>) -> some View {
        modifier(SwipeDelete(removal: removal, item: item))
    }
}
