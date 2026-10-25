import Foundation
import Observation

/// Owns one window's setup steps around phrase entry: preparing a new wallet, saving it once its backup is confirmed,
/// opening the saved wallet, and releasing an unsaved draft.
@MainActor
@Observable
final class WalletSetupModel {
    /// A secret-free error for the alert.
    var error: OnboardingError?
    /// The accepted request to prepare a new wallet, while it waits for the scene's task or runs.
    private(set) var creation: UUID?
    /// The accepted request to save the backed-up wallet, while it waits for the scene's task or runs.
    private(set) var completion: UUID?
    /// Whether a new wallet's recovery words are ready to back up; the scene shows them when they are.
    private(set) var isPrepared = false
    private let coordinator: any OnboardingCoordinating
    private let providers: ProvidersCoordinator

    /// Creates the model around the window's onboarding coordinator and provider choice.
    /// - Parameters:
    ///   - coordinator: The sole owner of recovery preparation, persistence, and routing.
    ///   - providers: The window's provider choice, whose waiting change keeps the saved wallet from opening.
    init(coordinator: any OnboardingCoordinating, providers: ProvidersCoordinator) {
        self.coordinator = coordinator
        self.providers = providers
    }

    /// Whether a new wallet is being prepared, waits for its backup, or is being saved, so other setup steps wait.
    var isPending: Bool { creation != nil || completion != nil || isPrepared }

    /// Accepts one request to prepare a new wallet; taps while setup work runs are ignored.
    func create() {
        guard !coordinator.isWorking, !isPending else { return }
        error = nil
        creation = UUID()
    }

    /// Prepares the accepted wallet in the scene's SwiftUI-managed task; a cancelled preparation releases its draft.
    /// - Parameter creation: The request captured by the owning view task.
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

    /// Accepts one request to save the prepared wallet after the person confirms its backup.
    func save() {
        guard completion == nil else { return }
        error = nil
        completion = UUID()
    }

    /// Saves the backed-up wallet in the scene's SwiftUI-managed task; a failed save keeps its words for another try.
    /// - Parameter completion: The request captured by the owning view task.
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

    /// Ends the backup step when the person goes back from it, and releases the draft once no work holds it.
    func leaveBackup() {
        completion = nil
        isPrepared = false
        if !coordinator.isWorking { discardDraft() }
    }

    /// Opens the saved wallet with the provider in use.
    ///
    /// Taps while a provider change waits to be saved are ignored, so the wallet never opens on the previous provider.
    /// Saving a choice is quick, so the button shows no waiting state.
    func open() {
        guard providers.attempt == nil else { return }
        do {
            try coordinator.finish()
        } catch {
            self.error = .openFailed
        }
    }

    /// Releases the unsaved draft without reporting secret-bearing errors.
    func discardDraft() {
        if let error = coordinator.releaseDraft() { self.error = error }
    }
}
