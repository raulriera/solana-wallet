import SwiftUI
@testable import widgets

/// Applies a window's restoration to its network and section, as a window's root does.
struct WindowRestorationRoot: View {
    @Bindable var choices: WindowChoices
    let startup: any WindowStarting
    let router: any WindowRouting

    var body: some View {
        Color.clear
            .windowRestoration(startup, router: router, attempt: 0, network: $choices.network,
                               section: $choices.section)
    }
}
