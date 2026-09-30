import OSLog
import SwiftUI

/// Checks Settings recovery for each window's activation without changing its content or navigation.
struct AppearanceLifecycle: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    private let appearance: any AppearanceCoordinating
    private let logger = Logger(subsystem: "Appearance", category: "Recovery")

    /// Connects a window to the application-owned appearance coordinator.
    /// - Parameter appearance: The shared coordinator used by every wallet window.
    init(appearance: any AppearanceCoordinating) {
        self.appearance = appearance
    }

    /// Runs recovery when this window first becomes active and on subsequent activations.
    /// - Parameter content: The window's existing content.
    /// - Returns: Unchanged content with a lifecycle-bound activation task.
    func body(content: Content) -> some View {
        content.task(id: scenePhase) {
            guard scenePhase == .active else { return }
            do { try await appearance.activate() }
            catch {
                // Retain the request so the next activation can attempt recovery again.
                logger.error("Could not load or reset appearance: \(String(describing: error), privacy: .private)")
            }
        }
    }
}
