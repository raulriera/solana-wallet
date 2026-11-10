import Foundation
import Observation

/// Checks and saves a provider entry, such as an API key or a URL.
@MainActor
@Observable
final class ProviderSetupModel<EntryError: ProviderEntryError>: ProviderSubmitting, Identifiable {
    private(set) var rejection: EntryError?
    private(set) var rejectionCount = 0
    var error: EntryError?
    private(set) var attempt: UUID?
    var isPending: Bool { attempt != nil }
    private(set) var isSaved = false
    @ObservationIgnored private var pendingEntry: String?
    private let connection: any ProviderConnecting<EntryError>

    /// Creates a model that checks entries with a provider connection.
    ///
    /// - Parameter connection: The connection that checks and saves the entry.
    init(connection: any ProviderConnecting<EntryError>) {
        self.connection = connection
    }

    func submit(_ entry: String) {
        guard attempt == nil else { return }
        pendingEntry = entry.trimmingCharacters(in: .whitespacesAndNewlines)
        attempt = UUID()
    }

    /// Checks and saves one accepted entry.
    ///
    /// - Parameter attempt: The ID of the attempt to run.
    func run(_ attempt: UUID?) async {
        guard let attempt, self.attempt == attempt, let entry = pendingEntry.take() else { return }
        defer { self.attempt = nil }
        do {
            try await connection.connect(entry)
            isSaved = true
        } catch let error as EntryError where error.rejectsEntry {
            guard !Task.isCancelled else { return }
            rejection = error
            rejectionCount += 1
        } catch {
            guard !Task.isCancelled, !(error is CancellationError) else { return }
            rejection = nil
            self.error = error as? EntryError ?? .unavailable
        }
    }
}

extension ProviderSetupModel: IdentityHashable {}
