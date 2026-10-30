import Foundation
import Observation

/// Runs one window's new wallet setup: preparing, saving, and opening the wallet.
@MainActor
@Observable
final class WalletSetupModel {
    var error: OnboardingError?
    /// The identifier of the waiting wallet preparation, or `nil` when none waits.
    private(set) var creation: UUID?
    /// The identifier of the waiting save, or `nil` when none waits.
    private(set) var completion: UUID?
    /// Whether a new wallet's recovery words are ready to back up.
    private(set) var isPrepared = false
    private let coordinator: any OnboardingCoordinating
    private let providers: ProvidersCoordinator

    /// Creates a setup model.
    ///
    /// - Parameters:
    ///   - coordinator: The window's onboarding coordinator.
    ///   - providers: The window's provider coordinator.
    init(coordinator: any OnboardingCoordinating, providers: ProvidersCoordinator) {
        self.coordinator = coordinator
        self.providers = providers
    }

    /// Whether a new wallet is being prepared, waits for its backup, or is being saved.
    var isPending: Bool { creation != nil || completion != nil || isPrepared }

    /// Requests a new wallet unless setup work is running.
    func create() {
        guard !coordinator.isWorking, !isPending else { return }
        error = nil
        creation = UUID()
    }

    /// Prepares the requested wallet.
    ///
    /// - Parameter creation: The identifier of the preparation to run.
    func prepare(_ creation: UUID?) async {
        guard let creation, self.creation == creation else { return }
        defer { self.creation = nil }
        do {
            try await coordinator.create()
            try Task.checkCancellation()
            isPrepared = true
        } catch {
            if Task.isCancelled || error is CancellationError {
                discardDraft()
            } else {
                self.error = .preparationFailed
            }
        }
    }

    /// Requests a save of the prepared wallet.
    func save() {
        guard completion == nil else { return }
        error = nil
        completion = UUID()
    }

    /// Saves the prepared wallet.
    ///
    /// - Parameter completion: The identifier of the save to run.
    func complete(_ completion: UUID?) async {
        guard let completion, self.completion == completion else { return }
        defer {
            self.completion = nil
            if Task.isCancelled { discardDraft() }
        }
        do {
            _ = try await coordinator.complete()
        } catch {
            guard !Task.isCancelled, !(error is CancellationError) else { return }
            self.error = .saveFailed
        }
    }

    /// Ends the backup step and releases the draft when no work holds it.
    func leaveBackup() {
        completion = nil
        isPrepared = false
        if !coordinator.isWorking { discardDraft() }
    }

    /// Opens the saved wallet unless a provider change waits.
    func open() {
        guard providers.attempt == nil else { return }
        do {
            try coordinator.finish()
        } catch {
            self.error = .openFailed
        }
    }

    /// Releases the unsaved draft.
    func discardDraft() {
        if let error = coordinator.releaseDraft() { self.error = error }
    }
}
