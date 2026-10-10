import Foundation

/// Reset failures stop startup instead of running a test against partially cleared state.
nonisolated enum UITestResetError: Error { case missingBundleIdentifier, keychain(OSStatus) }
