import SwiftUI

extension EnvironmentValues {
    /// Types a key into the payment's amount; `nil` outside the keypad screen, where no amount is typed.
    @Entry var pressKey: KeypadPressAction?
}
