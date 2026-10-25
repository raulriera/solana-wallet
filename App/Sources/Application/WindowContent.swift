import RPC
import SwiftUI

/// Shows a window's root destination, keeps the section it shows, runs the window's startup and reset lifecycles, and
/// gives the window a new portfolio when its network changes.
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
                OnboardingScene(coordinator: window.onboarding, providers: window.providers,
                                pasteboard: services.recoveryPasteboard)
                    .onboardingLifecycle()
            case .wallet(let account):
                WalletScene(section: $section, network: $network, account: account,
                            portfolio: window.portfolio, tokenRemoval: window.tokenRemoval,
                            privateBalance: window.privateBalance,
                            settings: window.settings, connection: services.providerConnection,
                            security: window.security, providers: window.providers)
            }
        }
        .animation(.default, value: window.router.destination)
        .windowRestoration(window.startup, router: window.router, attempt: startupAttempt, network: $network,
                           section: $section)
        .windowReset(services, router: window.router, onboarding: $window.onboarding, security: window.security,
                     providers: window.providers)
        .onChange(of: network) { window.show(network) }
    }
}
