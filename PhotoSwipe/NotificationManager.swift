import Foundation
import UserNotifications

/// Singleton manager responsible for handling all local push notifications.
/// Handles requesting user permissions, scheduling daily reminders, and canceling notifications.
class NotificationManager {
    /// Shared singleton instance of NotificationManager.
    static let shared = NotificationManager()
    
    /// Private initializer to enforce singleton pattern.
    private init() {}
    
    // MARK: - Authorization
    
    /// Requests user permission to display notifications with alert, sound, and badge options.
    /// - Parameter completion: Closure called with the authorization result (granted/denied).
    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            DispatchQueue.main.async {
                completion(granted)
            }
        }
    }
    
    // MARK: - Scheduling
    
    /// Schedules a daily reminder notification at a specific time.
    /// Automatically removes any previously scheduled reminders to avoid duplicates.
    /// The notification repeats daily at the same time.
    /// - Parameters:
    ///   - date: The time of day when the notification should be triggered.
    ///   - isTodayDone: Not used in the current implementation but available for future logic.
    func scheduleDailyNotification(at date: Date, isTodayDone: Bool) {
        // Remove any previous reminder to avoid duplicates.
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["daily_reminder"])
        
        // Use the selected time to create a repeating daily trigger.
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: date)
        
        let content = UNMutableNotificationContent()
        content.title = "Time to clean up! 📸"
        content.body = "Your daily memories are ready to be reviewed. Don't lose your streak!"
        content.sound = .default
        
        // Create a recurring notification trigger for the chosen time.
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: "daily_reminder", content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error scheduling notification: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Cancellation
    
    /// Cancels the scheduled daily reminder notification.
    /// Removes all pending notification requests with the "daily_reminder" identifier.
    func cancelNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["daily_reminder"])
    }
}
