import SwiftUI
import UIKit

/// A SwiftUI wrapper for UIDatePicker that provides a time selection interface.
/// Uses the wheel-style date picker for better user experience on iOS.
/// Supports custom minute intervals for flexible time selection.
struct CustomDatePicker: UIViewRepresentable {
    /// Binding to the selected date/time value.
    @Binding var selection: Date
    /// The interval in minutes for the time picker (e.g., 15 for 15-minute intervals).
    let minuteInterval: Int

    // MARK: - UIViewRepresentable Methods
    
    /// Creates and configures the underlying UIDatePicker view.
    /// - Returns: A configured UIDatePicker with wheel style and time mode.
    func makeUIView(context: Context) -> UIDatePicker {
        let picker = UIDatePicker()
        
        // Use the wheel style on recent iOS versions for a traditional time picker.
        picker.preferredDatePickerStyle = .wheels
        picker.datePickerMode = .time
        picker.minuteInterval = minuteInterval
        
        // Keep the picker centered within the available layout space.
        picker.setContentHuggingPriority(.defaultLow, for: .horizontal)
        
        picker.addTarget(context.coordinator, action: #selector(Coordinator.dateChanged(_:)), for: .valueChanged)
        return picker
    }

    /// Updates the UIDatePicker when the SwiftUI binding value changes externally.
    /// Only updates if the date actually changed to prevent the wheel from jumping during user interaction.
    func updateUIView(_ uiView: UIDatePicker, context: Context) {
        // Update the picker only when the bound value changes externally.
        // This prevents the wheel from jumping while the user is interacting with it.
        if uiView.date != selection {
            uiView.date = selection
        }
    }

    /// Creates a coordinator to handle interactions between UIDatePicker and SwiftUI.
    /// - Returns: A Coordinator instance that manages the date change callbacks.
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    /// Coordinator class that bridges UIDatePicker events to SwiftUI bindings.
    /// Handles date value changes from the UIDatePicker and updates the parent binding.
    class Coordinator: NSObject {
        /// Reference to the parent CustomDatePicker struct.
        let parent: CustomDatePicker

        /// Initializes the coordinator with a reference to the parent.
        /// - Parameter parent: The CustomDatePicker that owns this coordinator.
        init(_ parent: CustomDatePicker) {
            self.parent = parent
        }

        /// Handles date change events from the UIDatePicker.
        /// Updates the parent binding when the user changes the date.
        /// - Parameter sender: The UIDatePicker that triggered the event.
        @objc func dateChanged(_ sender: UIDatePicker) {
            parent.selection = sender.date
        }
    }
}
