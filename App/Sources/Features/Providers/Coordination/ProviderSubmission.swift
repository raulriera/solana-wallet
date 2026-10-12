import Accessibility
import Foundation
import Observation
import SwiftUI

/// Owns one window's checks of a provider entry, such as an API key or an RPC URL; the flow that asked for the
/// entry continues once it's saved.
@MainActor
@Observable
final class ProviderSubmission<EntryError: ProviderEntryError>: ProviderSubmitting, Identifiable, Equatable {
    /// The refused entry's explanation while it shows under the field.
    private(set) var rejection: EntryError?
    /// Counts refused entries, so each refusal signals again while its message stays on screen.
    private(set) var rejectionCount = 0
    var error: EntryError?
    private(set) var attempt: UUID?
    /// Whether an accepted entry is still being checked, so the screen keeps its input locked until it ends.
    var isPending: Bool { attempt != nil }
    /// Whether an accepted entry is saved; the flow that asked for it continues when it is.
    private(set) var isSaved = false
    @ObservationIgnored private var pendingEntry: String?
    private let connection: any ProviderConnecting<EntryError>

    /// Works with a shared provider connection.
    /// - Parameter connection: Checks and saves the entry, and tells every window.
    init(connection: any ProviderConnecting<EntryError>) {
        self.connection = connection
    }

    /// Compares submissions by identity, so assigning the same check again changes nothing.
    /// - Parameters:
    ///   - lhs: An entry check.
    ///   - rhs: Another entry check.
    /// - Returns: Whether both are the same entry check.
    nonisolated static func == (lhs: ProviderSubmission, rhs: ProviderSubmission) -> Bool {
        lhs === rhs
    }

    /// Accepts one entry; taps during a check are ignored.
    /// - Parameter entry: The text as entered, kept out of task identity; surrounding whitespace is dropped.
    func submit(_ entry: String) {
        guard attempt == nil else { return }
        pendingEntry = entry.trimmingCharacters(in: .whitespacesAndNewlines)
        attempt = UUID()
    }

    /// Checks one accepted entry in the screen's SwiftUI-managed task.
    ///
    /// The inline rejection changes only when a result arrives, so it never flashes during a check.
    /// A saved entry counts even if cancellation arrives afterwards.
    /// - Parameter attempt: The attempt captured by the owning view task.
    func run(_ attempt: UUID?) async {
        guard let attempt, self.attempt == attempt, let entry = pendingEntry.take() else { return }
        defer { self.attempt = nil }
        do {
            try await connection.connect(entry)
            isSaved = true
        } catch let error as EntryError where error.rejectsEntry {
            guard !Task.isCancelled else { return }
            withAnimation { rejection = error }
            rejectionCount += 1
            AccessibilityNotification.Announcement(String(localized: error.message)).post()
        } catch {
            guard !Task.isCancelled, !(error is CancellationError) else { return }
            withAnimation { rejection = nil }
            // Anything else stays generic, so no underlying error text reaches the alert.
            self.error = error as? EntryError ?? .unavailable
        }
    }
}
