import RPC
import SwiftUI

/// Shows a window's root destination, keeps the section it shows, and runs the window's startup and reset lifecycles.
struct WindowContent: View {
    @SceneStorage("window.section") private var section = WalletSection.portfolio
    @State private var startupAttempt = 0
    @Bindable var window: WindowModel
    /// The network that the window shows, kept with the window's scene state.
    @Binding var network: Network
    let services: AppServices

    var body: some View {
        ZStack {
            switch window.router.destination {
            case .restoringWallets:
                Color.clear
            case .walletRestorationFailed:
                WalletUnavailableScreen(retry: { startupAttempt += 1 })
            case .onboarding:
                OnboardingScene(coordinator: window.onboarding, providers: services.makeProvidersCoordinator(),
                                pasteboard: services.recoveryPasteboard)
                    .onboardingLifecycle()
            case .wallet:
                // The wallet destination always has an account, which Settings can replace with another.
                if let account = Binding($window.account) {
                    WalletScene(section: $section, network: $network, account: account, services: services)
                }
            }
        }
        .animation(.default, value: window.router.destination)
        .windowRestoration(window.startup, router: window.router, attempt: startupAttempt, network: $network,
                           section: $section)
        .windowReset(services, router: window.router, onboarding: $window.onboarding)
    }
}
