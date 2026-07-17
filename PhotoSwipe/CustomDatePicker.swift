import SwiftUI
import UIKit

struct CustomDatePicker: UIViewRepresentable {
    @Binding var selection: Date
    let minuteInterval: Int

    func makeUIView(context: Context) -> UIDatePicker {
        let picker = UIDatePicker()
        
        // --- CORREZIONE DELL'ERRORE ---
        // Sulle ultime versioni di iOS si usa .wheels impostando la preferredDatePickerStyle
        picker.preferredDatePickerStyle = .wheels
        picker.datePickerMode = .time
        picker.minuteInterval = minuteInterval
        
        // Allinea al centro
        picker.setContentHuggingPriority(.defaultLow, for: .horizontal)
        
        picker.addTarget(context.coordinator, action: #selector(Coordinator.dateChanged(_:)), for: .valueChanged)
        return picker
    }

    func updateUIView(_ uiView: UIDatePicker, context: Context) {
        // Protezione fondamentale: aggiorna la rotella solo se la data è cambiata esternamente,
        // altrimenti la rotella scatta e si blocca mentre l'utente la sta muovendo.
        if uiView.date != selection {
            uiView.date = selection
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject {
        let parent: CustomDatePicker

        init(_ parent: CustomDatePicker) {
            self.parent = parent
        }

        @objc func dateChanged(_ sender: UIDatePicker) {
            parent.selection = sender.date
        }
    }
}
