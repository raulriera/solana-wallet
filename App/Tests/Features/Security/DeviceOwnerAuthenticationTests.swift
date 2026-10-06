import Foundation
import LocalAuthentication
import Synchronization
import Testing
@testable import widgets

/// Verifies how device-owner authentication treats the system's answers, without showing a prompt.
@Suite(.timeLimit(.minutes(1)))
struct DeviceOwnerAuthenticationTests {
    /// The owner confirms with biometrics or the passcode, so the reset may continue.
    @Test
    func `Confirming the owner passes`() async throws {
        let context = OwnerContext()

        try await DeviceOwnerAuthentication(makeContext: { context }).confirmOwner(reason: "Reset the app")

        #expect(context.evaluatedPolicies == [.deviceOwnerAuthentication])
    }

    /// Without a passcode there's nothing to unlock, so the check passes without a prompt.
    @Test
    func `A device without a passcode passes without asking`() async throws {
        let context = OwnerContext(availability: LAError(.passcodeNotSet))

        try await DeviceOwnerAuthentication(makeContext: { context }).confirmOwner(reason: "Reset the app")

        #expect(context.evaluatedPolicies.isEmpty)
    }

    /// Dismissing the prompt reaches the screen as cancellation, so nothing opens.
    @Test
    func `Dismissing the prompt reports cancellation`() async {
        let context = OwnerContext(evaluation: LAError(.userCancel))

        await #expect(throws: CancellationError.self) {
            try await DeviceOwnerAuthentication(makeContext: { context }).confirmOwner(reason: "Reset the app")
        }
    }

    /// A failed authentication stops the reset.
    @Test
    func `A failed authentication stops the reset`() async {
        let context = OwnerContext(evaluation: LAError(.authenticationFailed))

        await #expect(throws: LAError.self) {
            try await DeviceOwnerAuthentication(makeContext: { context }).confirmOwner(reason: "Reset the app")
        }
    }
}

/// Answers availability and evaluation with scripted results and records each evaluation.
///
/// Safety: the scripted results never change, and the recorded policies are protected by a mutex.
/// Remove this unchecked conformance when the SDK supplies a Sendable context.
private final class OwnerContext: LAContext, @unchecked Sendable {
    private let availability: LAError?
    private let evaluation: LAError?
    private let policies = Mutex<[LAPolicy]>([])

    /// The policies the authentication evaluated, in order.
    var evaluatedPolicies: [LAPolicy] { policies.withLock { $0 } }

    /// Creates a context with scripted answers.
    /// - Parameters:
    ///   - availability: The error that makes the policy unavailable, if any.
    ///   - evaluation: The error the evaluation reports, if any.
    init(availability: LAError? = nil, evaluation: LAError? = nil) {
        self.availability = availability
        self.evaluation = evaluation
        super.init()
    }

    /// Reports the scripted availability.
    /// - Parameters:
    ///   - policy: The requested policy.
    ///   - error: Receives the scripted error when the policy is unavailable.
    /// - Returns: Whether the policy is available.
    override func canEvaluatePolicy(_ policy: LAPolicy, error: NSErrorPointer) -> Bool {
        guard let availability else { return true }
        error?.pointee = availability as NSError
        return false
    }

    /// Records the evaluation and replies with the scripted result.
    /// - Parameters:
    ///   - policy: The requested policy.
    ///   - localizedReason: The prompt's explanation.
    ///   - reply: Receives the scripted result.
    override func evaluatePolicy(_ policy: LAPolicy, localizedReason: String, reply: @escaping @Sendable (Bool, (any Error)?) -> Void) {
        policies.withLock { $0.append(policy) }
        reply(evaluation == nil, evaluation)
    }
}
