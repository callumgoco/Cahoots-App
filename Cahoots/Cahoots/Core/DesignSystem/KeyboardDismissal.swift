import SwiftUI
import UIKit

extension View {
    /// Adds a Done button above the software keyboard so pads without a return key can be dismissed.
    func keyboardDoneToolbar() -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { dismissKeyboard() }
            }
        }
    }

    /// Lets a downward drag on a scroll view dismiss the keyboard interactively.
    func interactiveKeyboardDismiss() -> some View {
        scrollDismissesKeyboard(.interactively)
    }
}

func dismissKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}
