import RPC
import SwiftUI

/// Shows a window's root destination, keeps the section it shows, and runs the window's startup.
struct WindowContent: View {
    @SceneStorage("window.section") private var section = WalletSection.portfolio
    @State private var startupAttempt = 0
    @Bindable var window: WindowModel
    /// The network that the window shows, kept with the window's scene state.
    @Binding var network: Network
    let services: AppServices

    var body: some View {
        ZStack {
            switch window.destination {
            case .restoringWallets:
                Color.clear
            case .walletRestorationFailed:
                WalletUnavailableScreen(retry: { startupAttempt += 1 })
            case .onboarding:
                OnboardingScene(account: $window.account, coordinator: services.makeOnboardingCoordinator(),
                                providers: services.makeProvidersCoordinator(), pasteboard: services.recoveryPasteboard)
            case .wallet(let account):
                // Settings can replace the account with another.
                WalletScene(section: $section, network: $network, account: $window[account: account],
                            services: services)
            }
        }
        // A renamed account changes the wallet's screens without animating the window.
        .animation(.default, value: window.destination.id)
        .windowRestoration(window, attempt: startupAttempt, network: $network, section: $section)
    }
}
