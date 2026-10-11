import Foundation
import Observation

/// Owns one Settings window's RPC provider choices and the key entry they need.
@MainActor
@Observable
final class ProvidersFlow: ProviderActions {
    /// The provider in use as last read, or `nil` before the first read, so no provider shows as in use.
    private(set) var selection: ProviderSettings.Provider?
    /// The key sheet's checks while it's open; each opening starts a new one.
    var keyEntry: ProviderSubmission?
    /// A secret-free error for the alert.
    var error: ProvidersError?
    /// The choice waiting for the screen's task, identified without secrets.
    private(set) var attempt: UUID?
    /// Tells every window when a provider change applies, including a saved key.
    let revision: Revision
    @ObservationIgnored private var pending: ProviderSettings.Provider?
    /// The provider to choose once key entry saves its key.
    @ObservationIgnored private var selectsAfterKey: ProviderSettings.Provider?
    private let providers: any ProviderSelecting
    private let connection: any ProviderConnecting

    /// Connects the flow to the shared provider services.
    /// - Parameters:
    ///   - providers: Reads and changes the provider that every window uses.
    ///   - connection: Verifies and saves the provider's API key.
    ///   - revision: Tells every window when a provider change applies.
    init(providers: any ProviderSelecting, connection: any ProviderConnecting, revision: Revision) {
        self.providers = providers
        self.connection = connection
        self.revision = revision
    }

    /// Chooses the provider that every window uses, asking for its key first when none is saved.
    ///
    /// Taps while another choice waits are ignored.
    /// - Parameter provider: The provider to use.
    func select(_ provider: ProviderSettings.Provider) {
        guard attempt == nil else { return }
        error = nil
        pending = provider
        attempt = UUID()
    }

    /// Shows a provider's details: Helius's are its key entry, which replaces the key; the provider in use stays.
    /// - Parameter provider: The provider whose details to show.
    func showDetails(for provider: ProviderSettings.Provider) {
        guard attempt == nil, provider.hasDetails else { return }
        openKeyEntry(continuing: nil)
    }

    /// Continues the choice that asked for a key, after key entry saves it.
    func keySaved() {
        guard let provider = selectsAfterKey.take() else { return }
        select(provider)
    }

    /// Reads the saved choice again; an unreadable choice keeps the last one read and explains the failure.
    func reload() async {
        do {
            let settings = try await providers.settings()
            guard !Task.isCancelled else { return }
            selection = settings.selection
        } catch is CancellationError {
            // The screen left before the choice was read.
        } catch {
            guard !Task.isCancelled else { return }
            self.error = .selectionUnreadable
        }
    }

    /// Ends the flow after a reset, dropping key entry, any waiting choice, and the choice last read.
    func close() {
        selectsAfterKey = nil
        keyEntry = nil
        attempt = nil
        pending = nil
        error = nil
        selection = nil
    }

    /// Runs the waiting choice once in the screen's SwiftUI-managed task.
    /// - Parameter attempt: The identifier the screen's task captured.
    func run(_ attempt: UUID?) async {
        guard let attempt, self.attempt == attempt, let provider = pending.take() else { return }
        defer { if self.attempt == attempt { self.attempt = nil } }
        do {
            try await providers.select(provider)
        } catch is CancellationError {
            // The screen left before the choice was saved.
        } catch ProviderClientError.missingKey {
            guard !Task.isCancelled, self.attempt == attempt else { return }
            openKeyEntry(continuing: provider)
        } catch {
            // A choice saved before its old logos failed to clear is in use, so only an unsaved choice is an error;
            // a choice that can't be read back counts as unsaved.
            let saved = try? await providers.settings()
            guard !Task.isCancelled, self.attempt == attempt, saved?.selection != provider else { return }
            self.error = .selectionUnsaved
        }
    }

    /// Opens key entry with a new key check.
    /// - Parameter provider: The provider to choose once the key is saved, or `nil` to keep the provider in use.
    private func openKeyEntry(continuing provider: ProviderSettings.Provider?) {
        selectsAfterKey = provider
        keyEntry = ProviderSubmission(connection: connection, revision: revision)
    }
}
