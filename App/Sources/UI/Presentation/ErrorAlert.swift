import SwiftUI

/// An error whose alert offers Try Again when repeating the step that failed can help.
protocol RetryableError: LocalizedError {
    /// Whether repeating the step that failed can help.
    var canRetry: Bool { get }
}

/// Presents a typed error in an alert titled by its description and explained by its recovery suggestion.
private struct ErrorAlert<Presented: LocalizedError, Actions: View>: ViewModifier {
    @Binding var error: Presented?
    let actions: (Presented) -> Actions

    /// Presents the alert while an error is set; any action clears the error.
    /// - Parameter content: The view that owns the error.
    /// - Returns: The view with error presentation.
    func body(content: Content) -> some View {
        content
            .alert(isPresented: $error.isPresented, error: error, actions: actions) { error in
                Text(error.recoverySuggestion ?? "")
            }
    }
}

extension View {
    /// Presents a typed error with an OK button; dismissing the alert clears the error.
    /// - Parameter error: The error to present, or `nil` while there's none.
    /// - Returns: A view that presents the error in an alert.
    func errorAlert<Presented: LocalizedError>(_ error: Binding<Presented?>) -> some View {
        errorAlert(error) { _ in Button("OK", role: .cancel) {} }
    }

    /// Presents a typed error with Try Again and Cancel when repeating the step that failed can help, or OK otherwise.
    /// - Parameters:
    ///   - error: The error to present, or `nil` while there's none.
    ///   - retry: Repeats the step that failed.
    /// - Returns: A view that presents the error in an alert.
    func errorAlert<Presented: RetryableError>(_ error: Binding<Presented?>, retry: @escaping () -> Void) -> some View {
        errorAlert(error) { presented in
            if presented.canRetry {
                Button("Try Again", action: retry)
            }
            Button(presented.canRetry ? "Cancel" : "OK", role: .cancel) {}
        }
    }

    /// Presents a typed error with the given actions; any action clears the error.
    /// - Parameters:
    ///   - error: The error to present, or `nil` while there's none.
    ///   - actions: The alert's buttons for the presented error.
    /// - Returns: A view that presents the error in an alert.
    func errorAlert<Presented: LocalizedError, Actions: View>(
        _ error: Binding<Presented?>, @ViewBuilder actions: @escaping (Presented) -> Actions
    ) -> some View {
        modifier(ErrorAlert(error: error, actions: actions))
    }
}
