import RPC
import SwiftUI

/// Shows a window's root destination and runs the window's startup, reset, and network lifecycles.
struct WindowContent: View {
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
                WalletScene(network: $network, account: account, portfolio: window.portfolio.coordinator,
                            tokenRemoval: window.portfolio.tokenRemoval, settings: window.settings,
                            connection: services.providerConnection, security: window.security,
                            providers: window.providers, resetRevision: services.resetRevision)
            }
        }
        .animation(.default, value: window.router.destination)
        .windowRestoration(window.startup, router: window.router, attempt: startupAttempt)
        .windowReset(services, router: window.router, onboarding: $window.onboarding, security: window.security,
                     providers: window.providers)
        .windowNetwork($network, portfolio: window.portfolio, resetRevision: services.resetRevision)
    }
}
