import SwiftUI
import Testing
import UIKit

/// Shows a SwiftUI view in its own key window on the test host's scene, so tests run real view lifetimes and presentations.
@MainActor
final class HostedWindow<Content: View> {
    /// The controller hosting the view under test; a test can replace its root view.
    let host: UIHostingController<Content>
    private let window: UIWindow
    private let previousKeyWindow: UIWindow?

    /// Makes the view the content of a new key window on the test host's active scene.
    /// - Parameter content: The view under test.
    /// - Throws: A failed prerequisite when the test host has no active window scene.
    init(_ content: Content) throws {
        let scene = try #require(UIApplication.shared.connectedScenes.lazy.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        previousKeyWindow = scene.windows.first(where: \.isKeyWindow)
        window = UIWindow(windowScene: scene)
        host = UIHostingController(rootView: content)
        window.rootViewController = host
        window.makeKeyAndVisible()
    }

    /// Waits for the hosted view to present a view controller, such as a system dialog.
    /// - Parameter limit: How long to wait before giving up.
    /// - Returns: Whether the host presented a view controller in time.
    /// - Throws: `CancellationError` when the test is cancelled while waiting.
    func presentsViewController(within limit: Duration = .seconds(5)) async throws -> Bool {
        let deadline = ContinuousClock.now + limit
        while host.presentedViewController == nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        return host.presentedViewController != nil
    }

    /// Removes the window and its presentations, and makes the previous key window key again.
    func close() {
        host.presentedViewController?.dismiss(animated: false)
        window.isHidden = true
        window.rootViewController = nil
        previousKeyWindow?.makeKey()
    }
}
