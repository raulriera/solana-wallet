import SwiftUI

/// Turns private balances on from SOL's details: one attempt at a time, with a haptic and a VoiceOver announcement
/// when it succeeds, and an alert when it fails; and presents moves of SOL between the account's balances.
private struct PrivateBalanceLifecycle: ViewModifier {
    @Bindable var model: PrivateBalanceModel

    func body(content: Content) -> some View {
        let attempt = model.attempt
        content
            .task(id: attempt) { await model.run(attempt) }
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
    /// Runs turning private balances on from the token's details.
    /// - Returns: The details with turning private balances on.
    func privateBalanceLifecycle() -> some View {
        modifier(PrivateBalanceLifecycle(model: privateBalance))
    }
}
