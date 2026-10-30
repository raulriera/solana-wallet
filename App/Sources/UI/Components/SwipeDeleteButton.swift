import SwiftUI

/// A swipe action that asks to delete a row's item.
struct SwipeDeleteButton<Item>: View {
    /// The item waiting for confirmation of its deletion.
    @Binding var removal: Item?
    let item: Item

    var body: some View {
        Button("Delete", systemImage: "trash") { removal = item }
            .swipeActionTint(.red)
    }
}
