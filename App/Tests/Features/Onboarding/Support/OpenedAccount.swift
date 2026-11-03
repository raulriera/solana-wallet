import Observation
@testable import widgets

@MainActor
@Observable
final class OpenedAccount {
    var account: widgets.Account?
}
