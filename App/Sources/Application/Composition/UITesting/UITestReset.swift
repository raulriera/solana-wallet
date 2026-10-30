#if DEBUG && targetEnvironment(simulator)
import Foundation
import Security

/// Clears the app's saved data for a UI-test launch on the simulator.
enum UITestReset {
    /// Clears the Keychain items, files, and preferences when the launch requests a UI-test reset.
    ///
    /// - Parameters:
    ///   - keychainServices: The Keychain services to clear.
    ///   - directories: The directories to delete.
    /// - Throws: A Keychain, file system, or bundle error if the reset can't finish.
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
