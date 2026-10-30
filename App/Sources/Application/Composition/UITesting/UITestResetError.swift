import Foundation

/// An error that stops a UI-test reset.
nonisolated enum UITestResetError: Error { case missingBundleIdentifier, keychain(OSStatus) }
