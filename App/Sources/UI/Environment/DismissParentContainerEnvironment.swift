import SwiftUI

extension EnvironmentValues {
    /// The action that dismisses the container that provided it, such as a sheet, from any screen pushed inside it,
    /// or `nil` outside a container that provides it.
    @Entry var dismissParentContainer: DismissAction?
}
