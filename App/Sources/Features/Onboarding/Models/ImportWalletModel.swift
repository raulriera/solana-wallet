import Foundation
import Observation
import Vault
import Wallet

/// Owns one window's explicit import attempts while the existing coordinator owns its draft.
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

    /// Transient input, deliberately excluded from task and navigation identity.
    private struct Input {
        let phrase: String
        let passphrase: String
    }

    var isPending: Bool { attempt != nil || isRunning }

    /// Retains the window's existing workflow without creating another persistence service.
    /// - Parameter coordinator: The sole owner of recovery preparation, persistence, and routing.
    init(coordinator: any OnboardingCoordinating) {
        self.coordinator = coordinator
    }

    /// Opens phrase entry only after the preceding operation and its cleanup finish.
    func present() {
        guard !isPresented, !isPending, !coordinator.isWorking else { return }
        error = nil
        presentationID = UUID()
        ownsPresentation = true
        isPresented = true
    }

    /// Accepts one input snapshot synchronously, including before the view task starts.
    /// - Parameters:
    ///   - phrase: Locally validated recovery words.
    ///   - passphrase: The original passphrase, preserved verbatim.
    func submit(_ phrase: String, passphrase: String) {
        guard isPresented, !isPending, !coordinator.isWorking, coordinator.account == nil else { return }
        pendingInput = Input(phrase: phrase, passphrase: passphrase)
        error = nil
        attempt = UUID()
    }

    /// Runs an accepted attempt once in the destination's SwiftUI-managed task.
    /// - Parameter attempt: A non-secret identifier captured by the owning view task.
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
            // Back invalidates the attempt before SwiftUI delivers task cancellation.
            guard isPresented, self.attempt == attempt else { throw CancellationError() }
            isPreparing = false
            _ = try await coordinator.complete()
            // Completion owns the commit boundary, including a successful late cancellation.
        } catch {
            guard isPresented, !Task.isCancelled, !(error is CancellationError) else { return }
            self.error = switch error {
            case OnboardingCoordinatorError.discoveryRateLimited: .rateLimited
            default: isPreparing ? .preparationFailed : .saveFailed
            }
        }
    }

    /// Ends only the matching destination, so a late disappearance cannot cancel its replacement.
    /// - Parameter presentationID: The non-secret identity captured by the disappearing destination.
    func leave(_ presentationID: UUID?) {
        guard self.presentationID == presentationID else { return }
        isPresented = false
    }

    /// Invalidates work synchronously when Back changes the navigation binding.
    private func endPresentation() {
        guard ownsPresentation else { return }
        ownsPresentation = false
        attempt = nil
        pendingInput = nil
        error = nil
        if !isRunning { discardDraft() }
    }

    /// Reuses matching recovery or replaces only the in-memory draft for changed input.
    /// - Throws: Validation, cancellation, or the coordinator's secret-free preparation error.
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

    /// Releases references without deleting records or retaining underlying errors.
    private func discardDraft() {
        if let error = coordinator.releaseDraft() { self.error = error }
    }
}
