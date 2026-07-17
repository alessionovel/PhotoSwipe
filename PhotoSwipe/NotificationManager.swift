import Foundation
import UserNotifications

class NotificationManager {
    static let shared = NotificationManager()
    private init() {}
    
    // Richiede i permessi all'utente
    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            DispatchQueue.main.async {
                completion(granted)
            }
        }
    }
    
    // Schedula la notifica quotidiana
    func scheduleDailyNotification(at date: Date, isTodayDone: Bool) {
        // Rimuoviamo prima eventuali notifiche vecchie per evitare duplicati
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["daily_reminder"])
        
        // Se l'utente ha già completato lo swipe di oggi, non pianifichiamo la notifica per oggi (evita disturbi inutili)
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: date)
        
        let content = UNMutableNotificationContent()
        content.title = "Time to clean up! 📸"
        content.body = "Your daily memories are ready to be reviewed. Don't lose your streak!"
        content.sound = .default
        
        // Trigger ricorrente ogni giorno all'ora stabilita
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: "daily_reminder", content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error scheduling notification: \(error.localizedDescription)")
            }
        }
    }
    
    // Disattiva i promemoria
    func cancelNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["daily_reminder"])
    }
}//
//  NotificationManager.swift
//  PhotoSwipe
//
//  Created by Alessio Novel on 17/07/2026.
//

