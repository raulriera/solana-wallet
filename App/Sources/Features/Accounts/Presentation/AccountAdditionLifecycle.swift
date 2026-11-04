import SwiftUI

/// A modifier that runs account additions and presents their errors.
struct AccountAdditionLifecycle: ViewModifier {
    @Environment(\.accountCreation) private var creation
    @Environment(AccountStore.self) private var store
    @Bindable var addition: AccountAdditionModel

    func body(content: Content) -> some View {
        let attempt = addition.attempt
        content
            .task(id: attempt) {
                guard let creation else { return }
                await addition.run(attempt, creation: creation, store: store)
            }
            .alert(error: $addition.error, retry: addition.retry)
    }
}
