import SwiftUI

/// A borderless button style that shows only a label's icon.
struct MoreInfoButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button(configuration)
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
    }
}

extension PrimitiveButtonStyle where Self == MoreInfoButtonStyle {
    /// A borderless style that shows only a label's icon.
    static var moreInfo: Self { Self() }
}

extension Button where Label == SwiftUI.Label<Text, Image> {
    /// Creates a button that opens an item's details and names the item for VoiceOver.
    ///
    /// - Parameters:
    ///   - name: The name of the item.
    ///   - action: The action that opens the details.
    init(moreInfoAbout name: LocalizedStringResource, action: @escaping @MainActor () -> Void) {
        self.init(action: action) {
            SwiftUI.Label {
                Text("More Info About \(Text(name))", comment: "An info button's label. The variable is the item's name.")
            } icon: {
                Image(systemName: "info.circle")
            }
        }
    }
}
