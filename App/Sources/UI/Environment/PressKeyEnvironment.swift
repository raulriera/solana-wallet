import SwiftUI

extension EnvironmentValues {
    /// The action that types a key into the amount, or `nil` outside the keypad.
    @Entry var pressKey: KeypadPressAction?
}
