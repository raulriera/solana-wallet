import SwiftUI
@testable import widgets

struct WindowRestorationRoot: View {
    @Bindable var choices: WindowChoices
    let window: WindowModel

    var body: some View {
        Color.clear
            .windowRestoration(window, attempt: 0, network: $choices.network, section: $choices.section)
    }
}
