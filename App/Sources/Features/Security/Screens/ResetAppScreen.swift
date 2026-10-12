import SwiftUI

/// Explains what a reset deletes before the final confirmation.
struct ResetAppScreen: View {
    @Environment(\.palette) private var palette
    @State private var contentInset = LayoutMetrics.contentMargin
    let mode: ResetMode
    let account: Account
    let flow: SecurityFlow

    /// The explanation for why the user is resetting.
    private var message: LocalizedStringResource {
        switch mode {
        case .standard:
            "Resetting deletes every wallet, recovery phrase, your RPC API key, and custom RPCs from this device. Every window returns to Welcome. Your themes stay. Only your written recovery phrase can restore your wallets."
        case .recoveryUnavailable:
            "This device no longer has your wallet's recovery phrase, so resetting is the only fix. Resetting deletes every wallet, your RPC API key, and custom RPCs from this device. Every window returns to Welcome. Then import your written backup."
        }
    }

    var body: some View {
        Form {
            Section {} footer: {
                Text(message)
                    .foregroundStyle(palette.secondaryText)
            }

            if mode == .standard {
                Section {
                    Button("Show Recovery Phrase") { flow.showRecovery(for: account) }
                        .foregroundStyle(palette.accent)
                } footer: {
                    Text("Make sure you've written down your recovery phrase before you continue.")
                        .foregroundStyle(palette.secondaryText)
                }
                .listRowBackground(palette.surface)
            }
        }
        .scrollContentBackground(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        .readableContentMargins(inset: $contentInset)
        .safeAreaBar(edge: .bottom) {
            Button("Continue") { flow.confirmReset() }
                .buttonStyle(.primary)
                .padding(.horizontal, contentInset)
                .padding(.vertical, LayoutMetrics.actionBarVerticalPadding)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.background)
        .navigationTitle("Reset App")
        .navigationBarTitleDisplayMode(.inline)
    }
}
