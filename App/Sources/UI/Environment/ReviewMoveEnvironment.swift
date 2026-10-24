import SwiftUI

extension EnvironmentValues {
    /// Reviews a move's typed amount; `nil` outside a move's keypad, where nothing can be reviewed.
    @Entry var reviewMove: BalanceMoveReviewAction?
}
