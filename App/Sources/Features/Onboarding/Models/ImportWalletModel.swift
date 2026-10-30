import Foundation
import Observation
import Vault
import Wallet

/// Runs one window's wallet imports.
@MainActor
@Observable
final class ImportWalletModel: ImportSubmitting {
    var isPresented = false {
        didSet {
            if !isPresented { endPresentation() }
        }
    }
    var error: OnboardingError?
    private(set) var presentationID: UUID?
    private(set) var attempt: UUID?
    private var isRunning = false
    private var ownsPresentation = false
    @ObservationIgnored private var pendingInput: Input?
    private let coordinator: any OnboardingCoordinating

    /// The recovery words and passphrase of an import.
    private struct Input {
        let phrase: String
        let passphrase: String
    }

    var isPending: Bool { attempt != nil || isRunning }

    /// Creates an import model.
    ///
    /// - Parameter coordinator: The window's onboarding coordinator.
    init(coordinator: any OnboardingCoordinating) {
        self.coordinator = coordinator
    }

    /// Opens phrase entry unless work is running.
    func present() {
        guard !isPresented, !isPending, !coordinator.isWorking else { return }
        error = nil
        presentationID = UUID()
        ownsPresentation = true
        isPresented = true
    }

    func submit(_ phrase: String, passphrase: String) {
        guard isPresented, !isPending, !coordinator.isWorking, coordinator.account == nil else { return }
        pendingInput = Input(phrase: phrase, passphrase: passphrase)
        error = nil
        attempt = UUID()
    }

    /// Runs the waiting import.
    ///
    /// - Parameter attempt: The identifier of the import to run.
    func run(_ attempt: UUID?) async {
        guard let attempt, self.attempt == attempt, isPresented, !isRunning else { return }
        isRunning = true
        var isPreparing = true
        defer {
            pendingInput = nil
            self.attempt = nil
            isRunning = false
            if !isPresented || Task.isCancelled { discardDraft() }
        }

        do {
            try Task.checkCancellation()
            try await prepareInput()
            try Task.checkCancellation()
            guard isPresented, self.attempt == attempt else { throw CancellationError() }
            isPreparing = false
            _ = try await coordinator.complete()
        } catch {
            guard isPresented, !Task.isCancelled, !(error is CancellationError) else { return }
            self.error = switch error {
            case OnboardingCoordinatorError.discoveryRateLimited: .rateLimited
            default: isPreparing ? .preparationFailed : .saveFailed
            }
        }
    }

    /// Closes phrase entry when it's the given presentation.
    ///
    /// - Parameter presentationID: The identifier of the presentation that left.
    func leave(_ presentationID: UUID?) {
        guard self.presentationID == presentationID else { return }
        isPresented = false
    }

    /// Cancels the waiting import and releases the draft.
    private func endPresentation() {
        guard ownsPresentation else { return }
        ownsPresentation = false
        attempt = nil
        pendingInput = nil
        error = nil
        if !isRunning { discardDraft() }
    }

    /// Prepares a draft from the waiting input, keeping a draft that matches it.
    ///
    /// - Throws: A validation, cancellation, or preparation error.
    private func prepareInput() async throws {
        guard let input = pendingInput.take() else { throw CancellationError() }
        if let recovery = coordinator.recovery {
            let phrase = try RecoveryPhrase(input.phrase)
            if recovery.phrase.words == phrase.words,
               recovery.passphrase.utf8.elementsEqual(input.passphrase.utf8) { return }
            try coordinator.discard()
        }
        try await coordinator.importRecovery(input.phrase, passphrase: input.passphrase)
    }

    /// Releases the coordinator's unsaved draft.
    private func discardDraft() {
        if let error = coordinator.releaseDraft() { self.error = error }
    }
}
