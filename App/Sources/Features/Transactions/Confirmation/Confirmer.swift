import RPC

/// Observes one accepted transaction through bounded, cancellable status queries.
nonisolated struct Confirmer: TransactionConfirming {
    /// An observation failure that doesn't establish an on-chain execution outcome.
    enum Failure: Error, Sendable, Equatable {
        /// The provider serves a different network from the submission.
        case networkMismatch
        /// The response cannot describe the single requested signature consistently.
        case invalidResponse
        /// The observation deadline elapsed; the transaction's outcome remains unknown.
        case timedOut
    }

    private let rpc: any RPC
    private let clock: any Clock<Duration>

    /// Creates an observer with one-second polling and a 60-second deadline.
    ///
    /// - Parameters:
    ///   - rpc: The provider serving the submission's network.
    ///   - clock: The clock controlling delays; continuous time is the default.
    init(rpc: any RPC, clock: any Clock<Duration> = ContinuousClock()) {
        self.rpc = rpc
        self.clock = clock
    }

    /// Waits for confirmed execution while preserving failures as transaction outcomes.
    ///
    /// Missing, processed, and unspecified confirmation levels remain unresolved.
    /// RPC failures propagate without retries. The deadline cancels pending RPC work;
    /// as with all structured tasks, returning waits for dependencies to cooperate.
    /// No observation failure triggers rebuilding, resigning, or resubmission.
    ///
    /// - Parameter submission: The accepted signature and original network.
    /// - Returns: A confirmed or finalized execution outcome from the provider.
    /// - Throws: ``Failure``, an RPC error, or `CancellationError`.
    @concurrent
    func confirm(_ submission: Submission) async throws -> Confirmation {
        try Task.checkCancellation()
        guard rpc.network == submission.network else { throw Failure.networkMismatch }
        do {
            return try await withThrowingTaskGroup(of: Confirmation.self) { group in
                group.addTask { try await observe(submission) }
                group.addTask {
                    try await clock.sleep(for: .seconds(60))
                    try Task.checkCancellation()
                    throw Failure.timedOut
                }
                defer { group.cancelAll() }
                guard let confirmation = try await group.next() else { throw CancellationError() }
                try Task.checkCancellation()
                return confirmation
            }
        } catch {
            try Task.checkCancellation()
            throw error
        }
    }

    /// Polls status history until the provider observes at least confirmed commitment.
    ///
    /// - Parameter submission: The transaction to observe without broadcasting.
    /// - Returns: Its confirmed or finalized outcome.
    /// - Throws: A response, RPC, or cancellation error.
    private func observe(_ submission: Submission) async throws -> Confirmation {
        while true {
            try Task.checkCancellation()
            let response = try await rpc.send(GetSignatureStatuses(
                signatures: [submission.signature], searchesTransactionHistory: true
            ))
            try Task.checkCancellation()
            guard response.value.count == 1 else { throw Failure.invalidResponse }
            if let status = response.value[0] {
                guard status.slot <= response.context.slot else { throw Failure.invalidResponse }
                if let commitment = status.confirmationStatus, commitment != .processed {
                    return Confirmation(submission: submission, slot: status.slot, commitment: commitment,
                                        outcome: status.error.map(Confirmation.Outcome.failed) ?? .succeeded)
                }
            }
            try await clock.sleep(for: .seconds(1))
        }
    }
}
