#if DEBUG && targetEnvironment(simulator)
import Foundation
import Security

/// Clears the app's real persistent state only for an explicitly requested simulator UI-test launch.
enum UITestReset {
    /// Resets wallet recovery, private-balance keys and notes, the provider key and choice, every saved and cached
    /// file, and preferences before services are constructed.
    /// - Parameters:
    ///   - keychainServices: The same Keychain services used by production wallet, private-balance, and provider
    ///     storage.
    ///   - directories: The same directories that hold the app's kept and cached files.
    /// - Throws: A Keychain, filesystem, or app-configuration error if reset cannot complete.
    static func runIfRequested(keychainServices: [String], directories: [URL]) throws {
        guard ProcessInfo.processInfo.environment["UI_TEST_RESET"] == "1" else { return }
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { throw UITestResetError.missingBundleIdentifier }

        for service in keychainServices {
            let status = SecItemDelete([
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrSynchronizable as String: false,
                kSecUseDataProtectionKeychain as String: true,
            ] as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw UITestResetError.keychain(status) }
        }

        for directory in directories {
            do {
                try FileManager.default.removeItem(at: directory)
            } catch CocoaError.fileNoSuchFile {}
        }
        UserDefaults.standard.removePersistentDomain(forName: bundleIdentifier)
    }
}
#endif
