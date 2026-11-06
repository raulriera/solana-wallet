import SwiftUI

/// Asks the person to confirm an action in a confirmation dialog with system button colors.
private struct ActionConfirmation<Item, Message: View>: ViewModifier {
    @Environment(\.palette) private var palette
    let title: LocalizedStringResource
    let action: LocalizedStringResource
    let role: ButtonRole
    @Binding var item: Item?
    let perform: (Item) -> Void
    let message: (Item) -> Message

    func body(content: Content) -> some View {
        content
            .tint(palette.primary)
            .confirmationDialog(title, item: $item, titleVisibility: .visible) { item in
                Button(role: role) { perform(item) } label: { Text(action) }
            } message: { item in
                message(item)
            }
            .tint(nil)
    }
}

extension View {
    /// Asks the person to confirm an action on an item before performing it.
    ///
    /// - Parameters:
    ///   - title: The dialog's title.
    ///   - action: The name of the action.
    ///   - role: The role of the action's button.
    ///   - item: The item that waits for confirmation, cleared when the dialog closes.
    ///   - perform: The action that runs when the person confirms.
    ///   - message: The dialog's message for the item.
    /// - Returns: A view that asks for confirmation while the item is present.
    func confirmation<Item, Message: View>(
        _ title: LocalizedStringResource, action: LocalizedStringResource, role: ButtonRole = .destructive,
        item: Binding<Item?>, perform: @escaping (Item) -> Void,
        @ViewBuilder message: @escaping (Item) -> Message
    ) -> some View {
        modifier(ActionConfirmation(title: title, action: action, role: role, item: item, perform: perform,
                                    message: message))
    }

    /// Asks the person to confirm an action on an item before performing it, with no message.
    ///
    /// - Parameters:
    ///   - title: The dialog's title.
    ///   - action: The name of the action.
    ///   - role: The role of the action's button.
    ///   - item: The item that waits for confirmation, cleared when the dialog closes.
    ///   - perform: The action that runs when the person confirms.
    /// - Returns: A view that asks for confirmation while the item is present.
    func confirmation<Item>(
        _ title: LocalizedStringResource, action: LocalizedStringResource, role: ButtonRole = .destructive,
        item: Binding<Item?>, perform: @escaping (Item) -> Void
    ) -> some View {
        confirmation(title, action: action, role: role, item: item, perform: perform) { _ in EmptyView() }
    }

    /// Asks the person to confirm an action before performing it.
    ///
    /// - Parameters:
    ///   - title: The dialog's title.
    ///   - action: The name of the action.
    ///   - role: The role of the action's button.
    ///   - isPresented: Whether the dialog is showing.
    ///   - perform: The action that runs when the person confirms.
    ///   - message: The dialog's message.
    /// - Returns: A view that asks for confirmation while `isPresented` is `true`.
    func confirmation<Message: View>(
        _ title: LocalizedStringResource, action: LocalizedStringResource, role: ButtonRole = .destructive,
        isPresented: Binding<Bool>, perform: @escaping () -> Void,
        @ViewBuilder message: @escaping () -> Message
    ) -> some View {
        modifier(ActionConfirmation(title: title, action: action, role: role, item: isPresented.presented,
                                    perform: { perform() }, message: { message() }))
    }
}
