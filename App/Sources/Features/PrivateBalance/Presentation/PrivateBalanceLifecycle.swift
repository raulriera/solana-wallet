import RPC
import SwiftUI

/// Runs turning private balances on and presents balance moves.
private struct PrivateBalanceLifecycle: ViewModifier {
    @Environment(PrivateBalanceStore.self) private var privateBalances
    @Bindable var model: PrivateBalanceModel
    let account: Account
    let network: Network

    func body(content: Content) -> some View {
        let attempt = model.attempt
        content
            .task(id: attempt) { await model.run(attempt, in: privateBalances, for: account, on: network) }
            .errorAlert($model.error)
            .sheet(item: $model.move) { BalanceMoveSheet(move: $0) }
            .sensoryFeedback(.success, trigger: model.isTurnedOn) { _, isTurnedOn in isTurnedOn }
            .onChange(of: model.isTurnedOn) { _, isTurnedOn in
                guard isTurnedOn else { return }
                AccessibilityNotification.Announcement(String(localized: "Private balance turned on.")).post()
            }
    }
}

extension TokenDetailScreen {
    /// Runs turning private balances on and presents balance moves.
    ///
    /// - Returns: The screen with the private-balance lifecycle.
    func privateBalanceLifecycle() -> some View {
        modifier(PrivateBalanceLifecycle(model: privateBalance, account: account, network: network))
    }
}
