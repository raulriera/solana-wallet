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

/// Adds a trailing swipe action that confirms before deleting a row's item.
private struct ConfirmedSwipeDelete<Item, Message: View>: ViewModifier {
    @State private var removal: Item?
    /// The row's item, or `nil` for a row that can't be deleted.
    let item: Item?
    let title: LocalizedStringResource
    let perform: (Item) -> Void
    let message: (Item) -> Message

    func body(content: Content) -> some View {
        content
            .swipeDelete(item, removal: $removal)
            .confirmation(title, action: "Delete", item: $removal, perform: perform, message: message)
    }
}

extension View {
    /// Adds a trailing swipe action that confirms before deleting a row's item.
    ///
    /// - Parameters:
    ///   - item: The row's item, or `nil` for a row that can't be deleted.
    ///   - title: The confirmation's title.
    ///   - perform: The action that deletes the item.
    ///   - message: The confirmation's message for the item.
    /// - Returns: The row with its swipe action and confirmation.
    func swipeDelete<Item, Message: View>(
        _ item: Item?, title: LocalizedStringResource, perform: @escaping (Item) -> Void,
        @ViewBuilder message: @escaping (Item) -> Message
    ) -> some View {
        modifier(ConfirmedSwipeDelete(item: item, title: title, perform: perform, message: message))
    }

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
