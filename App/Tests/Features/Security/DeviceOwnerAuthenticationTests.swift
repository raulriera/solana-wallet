import Foundation
import LocalAuthentication
import Synchronization
import Testing
@testable import widgets

@Suite(.timeLimit(.minutes(1)))
struct DeviceOwnerAuthenticationTests {
    @Test
    func `Confirming the owner passes`() async throws {
        let context = OwnerContext()

        try await DeviceOwnerAuthentication(makeContext: { context }).confirmOwner(reason: "Reset the app")

        #expect(context.evaluatedPolicies == [.deviceOwnerAuthentication])
    }

    @Test
    func `A device without a passcode passes without asking`() async throws {
        let context = OwnerContext(availability: LAError(.passcodeNotSet))

        try await DeviceOwnerAuthentication(makeContext: { context }).confirmOwner(reason: "Reset the app")

        #expect(context.evaluatedPolicies.isEmpty)
    }

    @Test
    func `Dismissing the prompt reports cancellation`() async {
        let context = OwnerContext(evaluation: LAError(.userCancel))

        await #expect(throws: CancellationError.self) {
            try await DeviceOwnerAuthentication(makeContext: { context }).confirmOwner(reason: "Reset the app")
        }
    }

    @Test
    func `A failed authentication stops the reset`() async {
        let context = OwnerContext(evaluation: LAError(.authenticationFailed))

        await #expect(throws: LAError.self) {
            try await DeviceOwnerAuthentication(makeContext: { context }).confirmOwner(reason: "Reset the app")
        }
    }
}

private final class OwnerContext: LAContext, @unchecked Sendable {
    private let availability: LAError?
    private let evaluation: LAError?
    private let policies = Mutex<[LAPolicy]>([])

    var evaluatedPolicies: [LAPolicy] { policies.withLock { $0 } }

    init(availability: LAError? = nil, evaluation: LAError? = nil) {
        self.availability = availability
        self.evaluation = evaluation
        super.init()
    }

    override func canEvaluatePolicy(_ policy: LAPolicy, error: NSErrorPointer) -> Bool {
        guard let availability else { return true }
        error?.pointee = availability as NSError
        return false
    }

    override func evaluatePolicy(_ policy: LAPolicy, localizedReason: String, reply: @escaping @Sendable (Bool, (any Error)?) -> Void) {
        policies.withLock { $0.append(policy) }
        reply(evaluation == nil, evaluation)
    }
}
