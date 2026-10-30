import Foundation
import LocalAuthentication

/// Confirms the device owner with LocalAuthentication.
nonisolated struct DeviceOwnerAuthentication: OwnerAuthenticating {
    private let makeContext: @Sendable () -> LAContext

    /// Creates an authentication that uses the system's prompt.
    init() {
        self.init(makeContext: { LAContext() })
    }

    /// Creates an authentication that uses the given contexts.
    ///
    /// - Parameter makeContext: A closure that creates a new context for each request.
    init(makeContext: @escaping @Sendable () -> LAContext) {
        self.makeContext = makeContext
    }

    func confirmOwner(reason: String) async throws {
        let context = makeContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            if error?.code == LAError.Code.passcodeNotSet.rawValue { return }
            throw error ?? LAError(.biometryNotAvailable)
        }
        do {
            _ = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch let error as LAError where [.userCancel, .appCancel, .systemCancel].contains(error.code) {
            throw CancellationError()
        }
    }
}
