import Foundation
import RPC

/// Owns concurrent, single-attempt deliveries beyond the first acknowledgment.
///
/// The submitter owns this operation until acceptance; its receipt then owns it.
/// Releasing the last owner or explicitly cancelling stops pending HTTP operations.
nonisolated final class Broadcast: Sendable {
    /// The result of one provider's attempt, without an execution guarantee.
    struct Attempt: Sendable {
        /// The configured provider that received this attempt.
        let providerID: UUID
        /// A matching acknowledgment, or that provider's independent failure.
        let result: Result<Void, any Error>
    }

    /// All selected providers failed to acknowledge the locally known signature.
    struct Failure: Error, Sendable {
        /// The transaction identifier to use for status checks despite uncertain delivery.
        let signature: String
        /// The network on which delivery was attempted.
        let network: Network
        /// Each provider's diagnostic, including rate limits and retry delays.
        let attempts: [Attempt]
    }

    private let acceptance: AsyncStream<Void>
    private let operation: Task<[Attempt], Never>
    private let signature: String
    private let network: Network

    /// Starts every selected delivery without waiting for another provider's response.
    ///
    /// - Parameters:
    ///   - providers: The enabled providers already filtered to the transaction's network.
    ///   - request: The identical signed bytes and preflight options for every route.
    ///   - signature: The locally verified signature that acknowledgments must match.
    ///   - network: The transaction's selected network.
    init(providers: [Provider], request: SendTransaction, signature: String, network: Network) {
        self.signature = signature
        self.network = network
        let channel = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        acceptance = channel.stream
        // This task intentionally outlives the first acknowledgment. Ownership remains
        // with this object; the child requests themselves use structured concurrency.
        operation = Task { @concurrent in
            await withTaskGroup(of: Attempt.self) { group in
                for provider in providers {
                    group.addTask {
                        let result: Result<Void, any Error>
                        do {
                            try Task.checkCancellation()
                            let acknowledged = try await provider.rpc.send(request)
                            try Task.checkCancellation()
                            guard acknowledged == signature else {
                                throw Submitter.Failure.responseMismatch(expectedSignature: signature)
                            }
                            result = .success(())
                        } catch {
                            result = .failure(Task.isCancelled ? CancellationError() : error)
                        }
                        return Attempt(providerID: provider.id, result: result)
                    }
                }
                var attempts: [Attempt] = []
                var accepted = false
                for await attempt in group {
                    attempts.append(attempt)
                    if case .success = attempt.result, !accepted, !Task.isCancelled {
                        accepted = true
                        channel.continuation.yield(())
                        channel.continuation.finish()
                    }
                }
                channel.continuation.finish()
                return attempts
            }
        }
    }

    /// Cancels pending delivery when neither the caller nor a receipt owns the operation.
    deinit { operation.cancel() }

    /// Waits for the first matching acknowledgment without cancelling the other routes.
    ///
    /// - Throws: ``Failure`` if every attempt fails, or `CancellationError` if cancelled.
    func waitForAcceptance() async throws {
        try await withTaskCancellationHandler {
            for await _ in acceptance {
                try Task.checkCancellation()
                return
            }
            try Task.checkCancellation()
            let attempts = await operation.value
            try Task.checkCancellation()
            throw Failure(signature: signature, network: network, attempts: attempts)
        } onCancel: {
            operation.cancel()
        }
    }

    /// Waits for the independent provider diagnostics after all attempts finish.
    ///
    /// - Returns: One outcome per selected provider, in completion order.
    func results() async -> [Attempt] { await operation.value }

    /// Cancels unfinished attempts without revoking any transaction already delivered.
    func cancel() { operation.cancel() }
}
