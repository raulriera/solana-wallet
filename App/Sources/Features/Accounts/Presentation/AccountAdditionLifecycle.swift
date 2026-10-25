import SwiftUI

/// Runs each account addition while the accounts list is on screen and explains a failure.
struct AccountAdditionLifecycle: ViewModifier {
    @Environment(\.accountCreation) private var creation
    @Environment(AccountStore.self) private var store
    @Bindable var addition: AccountAdditionModel

    /// Awaits one addition at a time and presents its failure, with Try Again when it can help.
    /// - Parameter content: The accounts list.
    /// - Returns: The list with managed additions and failure presentation.
    func body(content: Content) -> some View {
        let attempt = addition.attempt
        content
            .task(id: attempt) {
                guard let creation else { return }
                await addition.run(attempt, creation: creation, store: store)
            }
            .errorAlert($addition.error, retry: addition.retry)
    }
}
