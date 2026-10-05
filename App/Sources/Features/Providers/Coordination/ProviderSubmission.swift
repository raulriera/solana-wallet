import Accessibility
import Foundation
import Observation
import SwiftUI

/// Owns one window's provider key checks, then continues the flow that asked for a key.
@MainActor
@Observable
final class ProviderSubmission: Identifiable {
    private(set) var isKeyRejected = false
    /// Counts rejected keys, so each rejection signals again while its message stays on screen.
    private(set) var rejectionCount = 0
    var failure: LocalizedStringResource?
    private(set) var attempt: UUID?
    @ObservationIgnored private var pendingKey: String?
    private let connection: any ProviderConnecting
    private let revision: ProviderKeyRevision
    private let finish: @MainActor () throws -> Void

    /// Pairs the shared provider connection with the step that follows a saved key.
    /// - Parameters:
    ///   - connection: Verifies and saves the provider's API key.
    ///   - revision: Tells every window when a key is saved.
    ///   - finish: Continues the owning flow once the key is saved, such as opening the wallet.
    init(connection: any ProviderConnecting, revision: ProviderKeyRevision, finish: @escaping @MainActor () throws -> Void) {
        self.connection = connection
        self.revision = revision
        self.finish = finish
    }

    /// Accepts one key; taps during a check are ignored.
    /// - Parameter key: The key as entered, kept out of task identity.
    func submit(_ key: String) {
        guard attempt == nil else { return }
        pendingKey = key
        attempt = UUID()
    }

    /// Checks one accepted key in the screen's SwiftUI-managed task, then finishes the owning flow.
    ///
    /// The inline rejection changes only when a result arrives, so it never flashes during a check.
    /// A saved key finishes the flow even if cancellation arrives afterwards.
    /// - Parameter attempt: The attempt captured by the owning view task.
    func run(_ attempt: UUID?) async {
        guard let attempt, self.attempt == attempt, let key = pendingKey.take() else { return }
        defer { self.attempt = nil }
        do {
            try await connection.connect(apiKey: key)
            revision.advance()
            try finish()
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
