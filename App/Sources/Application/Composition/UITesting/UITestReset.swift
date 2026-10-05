#if DEBUG && targetEnvironment(simulator)
import Foundation
import Security

/// Clears the app's real persistent state only for an explicitly requested simulator UI-test launch.
enum UITestReset {
    /// Reset failures stop startup instead of running a test against partially cleared state.
    enum Failure: Error { case missingBundleIdentifier, keychain(OSStatus) }

    /// Resets wallet recovery, the provider key, account metadata, and appearance before services are constructed.
    /// - Parameter keychainServices: The same Keychain services used by production wallet and provider storage.
    /// - Throws: A Keychain, filesystem, or app-configuration error if reset cannot complete.
    static func runIfRequested(keychainServices: [String]) throws {
        guard ProcessInfo.processInfo.environment["UI_TEST_RESET"] == "1" else { return }
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { throw Failure.missingBundleIdentifier }

        for service in keychainServices {
            let status = SecItemDelete([
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrSynchronizable as String: false,
                kSecUseDataProtectionKeychain as String: true,
            ] as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw Failure.keychain(status) }
        }

        for name in ["Accounts", "Themes"] {
            let directory = URL.applicationSupportDirectory.appending(path: name, directoryHint: .isDirectory)
            if FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.removeItem(at: directory)
            }
        }
        UserDefaults.standard.removePersistentDomain(forName: bundleIdentifier)
    }
}
#endif
