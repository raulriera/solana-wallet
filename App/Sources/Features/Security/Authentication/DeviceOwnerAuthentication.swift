import Foundation
import LocalAuthentication

/// Confirms the device owner with LocalAuthentication, using a fresh context for each request.
nonisolated struct DeviceOwnerAuthentication: OwnerAuthenticating {
    private let makeContext: @Sendable () -> LAContext

    /// Creates authentication that uses the system's prompt.
    init() {
        self.init(makeContext: { LAContext() })
    }

    /// Creates authentication with injected contexts for focused verification.
    /// - Parameter makeContext: Creates an unused context for each request.
    init(makeContext: @escaping @Sendable () -> LAContext) {
        self.makeContext = makeContext
    }

    /// Asks for biometrics or the device passcode, and returns without asking when the device has no passcode.
    /// - Parameter reason: A localized explanation shown in the system prompt.
    /// - Throws: `CancellationError` if the user dismisses the prompt, or the authentication error.
    func confirmOwner(reason: String) async throws {
        let context = makeContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // Without a passcode, iOS has already deleted every recovery phrase and nothing is left to unlock.
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
