import SwiftUI

/// Presents committed selection data without observing the full package workflow.
struct ThemeChooser: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let entries: [ThemeEntry]
    let scope: AppearancePreferences.Scope
    let selection: UUID?
    let isBusy: Bool
    let palette: RenderedPalette
    let onSelect: (UUID?) -> Void

    private var selectedID: UUID? { scope == .application ? selection ?? OriginalAppearance.id : selection }

    private var title: String { scope == .application ? "App Theme" : "Wallet Theme" }

    var body: some View {
        List {
            if case .wallet = scope {
                ThemeChoiceRow(name: "Use App Default", isSelected: selectedID == nil, palette: palette) {
                    onSelect(nil)
                }
            }
            ForEach(entries) { entry in
                ThemeChoiceRow(name: entry.name, isSelected: selectedID == entry.id, palette: palette) {
                    select(entry.id)
                }
            }
        }
        .animation(reduceMotion ? nil : .default, value: entries.map(\.id))
        .navigationTitle(title)
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(palette.background)
        .disabled(isBusy)
    }

    /// Sends an explicit wallet choice or the app's canonical Original selection.
    /// - Parameter id: The chosen built-in or custom identity.
    private func select(_ id: UUID) {
        onSelect(scope == .application && id == OriginalAppearance.id ? nil : id)
    }
}
