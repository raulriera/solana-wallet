import SwiftUI

/// A modifier that runs account deletions and presents their errors.
struct AccountDeletionLifecycle: ViewModifier {
    @Environment(AccountStore.self) private var store
    @Environment(TransactionStore.self) private var transactions
    @Bindable var deletion: AccountDeletionModel

    func body(content: Content) -> some View {
        let attempt = deletion.attempt
        content
            .task(id: attempt) { await deletion.run(attempt, store: store, transactions: transactions) }
            .errorAlert($deletion.error)
    }
}
