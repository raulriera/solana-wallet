import SwiftUI

/// A row's trailing swipe action that asks to delete the row's item.
///
/// Only the confirmation deletes, so the button has no destructive role and the row stays visible while asking.
struct SwipeDeleteButton<Item>: View {
    /// The item waiting for the person to confirm its deletion.
    @Binding var removal: Item?
    /// The row's item.
    let item: Item

    var body: some View {
        Button("Delete", systemImage: "trash") { removal = item }
            .labelStyle(.iconOnly)
            .foregroundStyle(.white)
            .tint(.red)
    }
}
