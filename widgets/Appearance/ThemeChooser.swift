import SwiftUI

/// Reuses the same native selection behavior for app defaults and wallet overrides.
struct ThemeChooser: View {
    let settings: AppearanceSettings
    let scope: AppearancePreferences.Scope
    let palette: RenderedPalette

    private var selectedID: UUID? {
        switch scope {
        case .application: settings.appearance.snapshot?.preferences.appThemeID ?? OriginalAppearance.id
        case .wallet(let id): settings.appearance.snapshot?.preferences.walletThemeIDs[id]
        }
    }

    var body: some View {
        List {
            if case .wallet = scope {
                choice("Use App Default", id: nil)
            }
            ForEach(settings.entries) { entry in
                choice(entry.name, id: entry.id)
            }
        }
        .navigationTitle(title)
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(palette.background)
        .disabled(settings.activity != nil)
    }

    private var title: String {
        switch scope {
        case .application: "App Theme"
        case .wallet: "Wallet Theme"
        }
    }

    /// Creates an accessible row whose checkmark always reflects committed state.
    /// - Parameters:
    ///   - name: The visible theme name or inheritance option.
    ///   - id: Its theme identity, or `nil` for wallet inheritance.
    /// - Returns: A native button with a selection trait for VoiceOver.
    private func choice(_ name: String, id: UUID?) -> some View {
        Button {
            let value = if case .application = scope, id == OriginalAppearance.id { nil as UUID? } else { id }
            settings.select(value, for: scope)
        } label: {
            HStack {
                Text(name).foregroundStyle(palette.primaryText)
                Spacer()
                if selectedID == id {
                    Image(systemName: "checkmark").foregroundStyle(palette.accent).accessibilityHidden(true)
                }
            }
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .listRowBackground(palette.surface)
        .listRowSeparatorTint(palette.separator)
        .accessibilityAddTraits(selectedID == id ? [.isSelected] : [])
    }
}
