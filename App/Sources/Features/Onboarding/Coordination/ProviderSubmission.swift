import Accessibility
import Foundation
import Observation
import SwiftUI

/// Owns one window's provider key checks after onboarding saves its wallet.
@MainActor
@Observable
final class ProviderSubmission {
    private(set) var isKeyRejected = false
    /// Counts rejected keys, so each rejection signals again while its message stays on screen.
    private(set) var rejectionCount = 0
    var failure: LocalizedStringResource?
    private(set) var attempt: UUID?
    @ObservationIgnored private var pendingKey: String?
    private let connection: any ProviderConnecting
    private let coordinator: any OnboardingCoordinating

    /// Pairs the shared provider connection with the window that saved the wallet.
    /// - Parameters:
    ///   - connection: Verifies and saves the provider's API key.
    ///   - coordinator: Opens the saved account once the key is saved.
    init(connection: any ProviderConnecting, coordinator: any OnboardingCoordinating) {
        self.connection = connection
        self.coordinator = coordinator
    }

    /// Accepts one key; taps during a check are ignored.
    /// - Parameter key: The key as entered, kept out of task identity.
    func submit(_ key: String) {
        guard attempt == nil else { return }
        pendingKey = key
        attempt = UUID()
    }

    /// Checks one accepted key in the screen's SwiftUI-managed task, then opens the wallet.
    ///
    /// The inline rejection changes only when a result arrives, so it never flashes during a check.
    /// A saved key opens the wallet even if cancellation arrives afterwards.
    /// - Parameter attempt: The attempt captured by the owning view task.
    func run(_ attempt: UUID?) async {
        guard let attempt, self.attempt == attempt, let key = pendingKey.take() else { return }
        defer { self.attempt = nil }
        do {
            try await connection.connect(apiKey: key)
            try coordinator.finish()
        } catch ProviderConnectionError.invalidKey {
            guard !Task.isCancelled else { return }
            withAnimation { isKeyRejected = true }
            rejectionCount += 1
            AccessibilityNotification.Announcement(String(localized: ProviderConnectionError.invalidKey.message)).post()
        } catch {
            guard !Task.isCancelled, !(error is CancellationError) else { return }
            withAnimation { isKeyRejected = false }
            // Anything else stays generic, so no underlying error text reaches the alert.
            failure = (error as? ProviderConnectionError ?? .unavailable).message
        }
    }
}
