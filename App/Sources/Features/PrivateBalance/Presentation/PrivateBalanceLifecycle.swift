import Portfolio
import RPC
import SwiftUI

/// Runs turning private balances on and presents balance moves and private sends.
private struct PrivateBalanceLifecycle: ViewModifier {
    @Environment(PrivateBalanceStore.self) private var privateBalances
    @Bindable var model: PrivateBalanceModel
    /// The account's public holding of the asset.
    let holding: Holding
    let account: Account
    let network: Network

    func body(content: Content) -> some View {
        let attempt = model.attempt
        content
            .environment(
                \.moveBalance,
                PrivateBalanceMoveAction(
                    model: model,
                    privateBalances: privateBalances,
                    account: account,
                    network: network,
                    holding: holding
                )
            )
            .environment(\.sendPrivately, PrivateSendAction(model: model))
            .task(id: attempt) { await model.run(attempt, in: privateBalances, for: account, on: network) }
            .alert(error: $model.error)
            .sheet(item: $model.sheet) { sheet in
                switch sheet {
                case .move(let move): BalanceMoveSheet(move: move)
                case .recipients: PrivateSendSheet(holding: holding, account: account, network: network)
                }
            }
            .sensoryFeedback(.success, trigger: model.isTurnedOn) { _, isTurnedOn in isTurnedOn }
            .onChange(of: model.isTurnedOn) { _, isTurnedOn in
                guard isTurnedOn else { return }
                AccessibilityNotification.Announcement(String(localized: "Private balance turned on.")).post()
            }
    }
}

extension TokenDetailScreen {
    /// Runs turning private balances on and presents balance moves and private sends.
    ///
    /// - Returns: The screen with the private-balance lifecycle.
    func privateBalanceLifecycle() -> some View {
        modifier(PrivateBalanceLifecycle(model: privateBalance, holding: holding, account: account, network: network))
    }
}
