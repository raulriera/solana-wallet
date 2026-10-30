import SwiftUI
import Testing
import UIKit

@MainActor
final class HostedWindow<Content: View> {
    let host: Host
    private let window: UIWindow
    private let previousKeyWindow: UIWindow?

    init(_ content: Content) throws {
        let scene = try #require(UIApplication.shared.connectedScenes.lazy.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        previousKeyWindow = scene.windows.first(where: \.isKeyWindow)
        window = UIWindow(windowScene: scene)
        host = Host(rootView: content)
        window.rootViewController = host
        window.makeKeyAndVisible()
    }

    func appears(within limit: Duration = .seconds(5)) async throws -> Bool {
        try await waits(within: limit) { host.hasAppeared }
    }

    func presentsViewController(within limit: Duration = .seconds(5)) async throws -> Bool {
        try await waits(within: limit) { host.presentedViewController != nil }
    }

    func closesPresentedViewController(within limit: Duration = .seconds(5)) async throws -> Bool {
        try await waits(within: limit) { host.presentedViewController == nil }
    }

    private func waits(within limit: Duration, until condition: () -> Bool) async throws -> Bool {
        let deadline = ContinuousClock.now + limit
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        return condition()
    }

    func close() {
        host.presentedViewController?.dismiss(animated: false)
        window.isHidden = true
        window.rootViewController = nil
        previousKeyWindow?.makeKey()
    }

    final class Host: UIHostingController<Content> {
        private(set) var hasAppeared = false

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            hasAppeared = true
        }
    }
}
