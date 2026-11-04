import SwiftUI

/// Loads a window's theme and provides its colors to the window's views.
private struct WindowAppearance: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var rendered = RenderedAppearance()
    @State private var error: ThemeError?
    let services: AppearanceServices

    private var palette: RenderedPalette { rendered.palette(scheme: colorScheme, contrast: contrast) }
    private var selectedTheme: ThemeEntry? { services.appearance.snapshot?.theme }

    func body(content: Content) -> some View {
        content
            .environment(\.palette, palette)
            .tint(palette.primary)
            .formStyle(.themed)
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                do { try await services.appearance.activate() }
                catch { report(error, as: .settingsUnreadable) }
            }
            .task(id: selectedTheme?.revision) { await loadSelectedTheme() }
            .errorAlert($error)
    }

    /// Loads the colors of the selected theme.
    private func loadSelectedTheme() async {
        let theme = selectedTheme
        do { try await rendered.load(theme, catalog: services.catalog, packages: services.packages) }
        catch {
            report(error, as: .themeUnreadable)
            if let theme, !Task.isCancelled { try? await services.appearance.forget(theme.id) }
        }
    }

    /// Shows an error unless the task is cancelled.
    ///
    /// - Parameters:
    ///   - error: The error that occurred.
    ///   - themeError: The error to show.
    private func report(_ error: any Error, as themeError: ThemeError) {
        guard !Task.isCancelled, !(error is CancellationError) else { return }
        self.error = themeError
    }
}

extension View {
    /// Loads a window's theme and provides its colors to this view's hierarchy.
    ///
    /// - Parameter services: The shared appearance services.
    /// - Returns: A view with the window's theme colors.
    func windowAppearance(services: AppearanceServices) -> some View {
        modifier(WindowAppearance(services: services))
    }
}
