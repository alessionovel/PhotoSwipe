import SwiftUI
import Photos
import AVKit
import AVFoundation

// MARK: - Data Models

/// Represents a user action taken during a swiping session (keeping or deleting a photo).
/// Used for implementing undo functionality and tracking session history.
struct SwipedAction {
    /// The photo item that was acted upon.
    let photoItem: PhotoItem
    /// Whether the photo was deleted (true) or kept (false).
    let wasDeleted: Bool
    /// The file size in MB of the deleted photo (0 if kept).
    let size: Double
}

/// Wrapper struct for a video asset to be displayed in fullscreen.
/// Conforms to Identifiable for SwiftUI fullscreen cover presentation.
struct VideoToPlay: Identifiable {
    /// Unique identifier for the video.
    let id = UUID()
    /// Reference to the underlying PHAsset video file.
    let asset: PHAsset
}

// MARK: - Main Content View

/// Main view of the PhotoSwipe app. Manages the overall app flow including:
/// - Home screen with statistics and session controls
/// - Swipe interface for reviewing and selecting photos to delete
/// - Settings sheet for configuring app preferences
/// - Video fullscreen player for viewing selected videos
struct ContentView: View {
    // MARK: - State Management
    
    /// Manager handling all photo library operations and session state.
    @StateObject private var photoManager = PhotoManager()
    /// Current drag offset for swipe gesture interaction.
    @State private var offset: CGSize = .zero
    
    // MARK: - Session State
    
    /// History of swipe actions to support undo functionality.
    @State private var swipeHistory: [SwipedAction] = []
    /// Array of photos selected for deletion in the current session.
    @State private var photosToDelete: [PhotoItem] = []
    /// Total size in MB of photos selected for deletion in the current session.
    @State private var currentSessionSavedMB: Double = 0.0
    
    // MARK: - Persistent State
    
    /// Total MB of photos and videos deleted across all sessions (persisted to device).
    @AppStorage("totalMBReleased") private var totalMBReleased: Double = 0.0
    /// Number of consecutive days the user has participated in photo cleanup (persisted to device).
    @AppStorage("dayStreak") private var dayStreak: Int = 0
    /// Date string of the last day the user completed the daily cleanup (persisted to device).
    @AppStorage("lastCheckDate") private var lastCheckDate: String = ""
    /// Whether a photo review session is currently in progress (persisted to device).
    @AppStorage("sessionInProgress") private var isSessionInProgress: Bool = false
    
    // MARK: - UI State
    
    /// Controls visibility of the swipe interface view.
    @State private var isShowingSwipeView = false
    /// Optional video to display in fullscreen player.
    @State private var videoToPlay: VideoToPlay? = nil
    /// Controls visibility of the settings sheet.
    @State private var isShowingSettings = false
    
    // MARK: - Theme
    
    /// Purple-to-indigo gradient used throughout the app for visual consistency.
    let themeGradient = LinearGradient(colors: [.purple, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing)
    
    // MARK: - Computed Properties
    
    /// Determines if the user has already completed today's cleanup task.
    /// - Returns: True if lastCheckDate matches today's date.
    private var isTodayDone: Bool {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return lastCheckDate == formatter.string(from: Date())
    }
    
    var body: some View {
        if photoManager.authorizationStatus == .denied || photoManager.authorizationStatus == .restricted ||
            photoManager.authorizationStatus == .limited {
            PermissionDeniedView()
        } else {
            NavigationStack {
                ZStack {
                    Color(.systemGroupedBackground).ignoresSafeArea()
                    
                    if isShowingSwipeView {
                        VStack {
                            // Top navigation bar for the swipe experience.
                            HStack {
                                Button(action: { isShowingSwipeView = false }) {
                                    HStack {
                                        Image(systemName: "chevron.left")
                                        Text("Home")
                                    }
                                    .font(.headline)
                                    .foregroundColor(.purple)
                                }
                                Spacer()
                                
                                // Show a pause button when there are items waiting to be deleted.
                                if !photosToDelete.isEmpty {
                                    Button(action: emptyTrashPartiallyAndExit) {
                                        HStack {
                                            Image(systemName: "trash.badge.cardposition")
                                            Text("Save & Pause")
                                        }
                                        .font(.subheadline).bold()
                                        .foregroundColor(.orange)
                                    }
                                    .padding(.trailing, 10)
                                }
                                
                                Button(action: undoLastSwipe) {
                                    HStack {
                                        Image(systemName: "arrow.uturn.backward")
                                        Text("Undo")
                                    }
                                    .font(.headline)
                                    .foregroundColor(swipeHistory.isEmpty ? .gray : .purple)
                                }
                                .disabled(swipeHistory.isEmpty)
                            }
                            .padding()
                            
                            // Progress bar for the current swipe session.
                            if !photoManager.isLoading {
                                let totalItems = photoManager.sessionTotalCount
                                if totalItems > 0 {
                                    VStack(spacing: 8) {
                                        // Count the items already completed in the current session.
                                        let itemsDone = photoManager.sessionViewedCount
                                        
                                        Text("\(itemsDone) / \(totalItems) COMPLETED")
                                            .font(.caption)
                                            .fontWeight(.bold)
                                            .foregroundColor(.gray)
                                        
                                        ProgressView(value: Double(itemsDone), total: Double(totalItems))
                                            .progressViewStyle(LinearProgressViewStyle(tint: .purple))
                                            .padding(.horizontal, 40)
                                    }
                                    .padding(.bottom, 10)
                                }
                            }
                            
                            Spacer()
                            
                            if photoManager.isLoading {
                                // Loading state while assets are being fetched.
                                VStack(spacing: 25) {
                                    ProgressView()
                                        .scaleEffect(1.5)
                                        .tint(.purple)
                                    Text(photoManager.loadingMessage)
                                        .font(.headline)
                                        .foregroundColor(.gray)
                                }
                            } else if let currentItem = photoManager.fetchedItems.first {
                                // Main swipe screen for reviewing photos and videos.
                                ZStack {
                                    RoundedRectangle(cornerRadius: 24)
                                        .fill(Color.black)
                                        .frame(width: 320, height: 430)
                                        .shadow(color: .purple.opacity(0.15), radius: 15, x: 0, y: 10)
                                    
                                    Image(uiImage: currentItem.image)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: 320, height: 430)
                                        .cornerRadius(24)
                                    
                                    if currentItem.isVideo {
                                        Button(action: {
                                            videoToPlay = VideoToPlay(asset: currentItem.asset)
                                        }) {
                                            Image(systemName: "play.circle.fill")
                                                .font(.system(size: 70))
                                                .foregroundColor(.white.opacity(0.9))
                                                .shadow(radius: 10)
                                        }
                                        
                                        VStack {
                                            HStack {
                                                Spacer()
                                                Text(formatDuration(currentItem.asset.duration))
                                                    .font(.caption).bold()
                                                    .padding(.horizontal, 8)
                                                    .padding(.vertical, 4)
                                                    .background(Color.black.opacity(0.6))
                                                    .foregroundColor(.white)
                                                    .cornerRadius(8)
                                                    .padding(16)
                                            }
                                            Spacer()
                                        }
                                    }
                                }
                                .overlay(
                                    ZStack {
                                        Text("KEEP")
                                            .font(.title).bold()
                                            .foregroundColor(.green)
                                            .padding()
                                            .background(Color.white.opacity(0.9))
                                            .cornerRadius(10)
                                            .opacity(offset.width > 20 ? Double(offset.width / 100) : 0)
                                            .position(x: 70, y: 50)
                                        
                                        Text("DELETE")
                                            .font(.title).bold()
                                            .foregroundColor(.red)
                                            .padding()
                                            .background(Color.white.opacity(0.9))
                                            .cornerRadius(10)
                                            .opacity(offset.width < -20 ? Double(-offset.width / 100) : 0)
                                            .position(x: 250, y: 50)
                                    }
                                )
                                .offset(x: offset.width, y: offset.height * 0.4)
                                .rotationEffect(.degrees(Double(offset.width / 12)))
                                .gesture(
                                    DragGesture()
                                        .onChanged { gesture in
                                            offset = gesture.translation
                                        }
                                        .onEnded { _ in
                                            if offset.width > 150 {
                                                withAnimation(.spring()) {
                                                    if !photoManager.fetchedItems.isEmpty {
                                                        let removed = photoManager.fetchedItems.removeFirst()
                                                        swipeHistory.append(SwipedAction(photoItem: removed, wasDeleted: false, size: 0))
                                                        // Mark the asset as viewed after keeping it.
                                                        photoManager.markAssetAsViewed(id: removed.asset.localIdentifier)
                                                    }
                                                    offset = .zero
                                                }
                                            } else if offset.width < -150 {
                                                withAnimation(.spring()) {
                                                    if !photoManager.fetchedItems.isEmpty {
                                                        let removed = photoManager.fetchedItems.removeFirst()
                                                        let photoSize = photoManager.getAssetSize(asset: removed.asset)
                                                        
                                                        swipeHistory.append(SwipedAction(photoItem: removed, wasDeleted: true, size: photoSize))
                                                        photosToDelete.append(removed)
                                                        currentSessionSavedMB += photoSize
                                                        // Mark the asset as viewed after deleting it.
                                                        photoManager.markAssetAsViewed(id: removed.asset.localIdentifier)
                                                    }
                                                    offset = .zero
                                                }
                                            } else {
                                                withAnimation(.spring()) { offset = .zero }
                                            }
                                        }
                                )
                                
                            } else if !photosToDelete.isEmpty {
                                // End-of-session screen when the current deck is finished.
                                VStack(spacing: 20) {
                                    Image(systemName: "trash.circle.fill")
                                        .font(.system(size: 80))
                                        .foregroundColor(.purple)
                                    
                                    Text("Ready to clean up?")
                                        .font(.title).bold()
                                    
                                    Text("You selected \(photosToDelete.count) photos to delete.")
                                        .font(.body)
                                        .foregroundColor(.gray)
                                    
                                    Text(String(format: "You will free up %.1f MB.", currentSessionSavedMB))
                                        .font(.headline)
                                    
                                    Button(action: {
                                        let assetsToDelete = photosToDelete.map { $0.asset }
                                        photoManager.deletePhotos(assets: assetsToDelete) { success in
                                            if success {
                                                totalMBReleased += currentSessionSavedMB
                                                photosToDelete.removeAll()
                                                swipeHistory.removeAll()
                                                currentSessionSavedMB = 0.0
                                                photoManager.clearSessionState() // Clear the partial session state.
                                                checkAndSetStreak() // Update the daily streak.
                                            }
                                        }
                                    }) {
                                        Text("Empty Trash (\(photosToDelete.count))")
                                            .font(.headline)
                                            .foregroundColor(.white)
                                            .frame(maxWidth: .infinity)
                                            .frame(height: 56)
                                            .background(themeGradient)
                                            .cornerRadius(16)
                                            .padding(.top, 20)
                                    }
                                }
                                .padding(30)
                                
                            } else {
                                VStack(spacing: 15) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 60))
                                        .foregroundColor(.purple)
                                    Text("All done for today!")
                                        .font(.title2).bold()
                                    Text("Come back tomorrow for more memories.")
                                        .foregroundColor(.gray)
                                }
                                .padding()
                                .onAppear {
                                    photoManager.clearSessionState() // Clear the session state when nothing remains to delete.
                                    checkAndSetStreak()
                                }
                            }
                            Spacer()
                        }
                    } else {
                        // Main home screen.
                        VStack(spacing: 0) {
                            HStack {
                                Spacer()
                                Button(action: { isShowingSettings = true }) {
                                    Image(systemName: "gearshape.fill")
                                        .font(.title2)
                                        .foregroundColor(.purple)
                                        .padding()
                                }
                            }
                            
                            VStack(spacing: 15) {
                                Image("AppLogo")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 100, height: 100)
                                    .cornerRadius(22)
                                    .shadow(color: .purple.opacity(0.3), radius: 10, x: 0, y: 5)
                                
                                Text("PhotoSwipe")
                                    .font(.system(size: 38, weight: .heavy, design: .rounded))
                                    .foregroundStyle(themeGradient)
                            }
                            .padding(.top, 10)
                            
                            Spacer()
                            
                            // Summary statistics for saved space and streak progress.
                            VStack(spacing: 20) {
                                HStack {
                                    Image(systemName: "trash.fill")
                                        .font(.title)
                                        .foregroundColor(.purple)
                                        .frame(width: 50)
                                    
                                    VStack(alignment: .leading) {
                                        Text("Total Space Saved")
                                            .font(.subheadline)
                                            .foregroundColor(.gray)
                                        if totalMBReleased < 1000 {
                                            Text(String(format: "%.1f MB", totalMBReleased))
                                                .font(.title2).bold()
                                        } else {
                                            Text(String(format: "%.2f GB", totalMBReleased / 1000.0))
                                                .font(.title2).bold()
                                        }
                                    }
                                    Spacer()
                                }
                                .padding()
                                .background(Color(.secondarySystemGroupedBackground))
                                .cornerRadius(16)
                                
                                HStack {
                                    Image(systemName: "flame.fill")
                                        .font(.title)
                                    // Highlight the streak icon when the day is already completed.
                                        .foregroundColor(isTodayDone ? .orange : Color(.systemGray3))
                                        .frame(width: 50)
                                    // Slightly enlarge the icon when the streak is active.
                                        .scaleEffect(isTodayDone ? 1.1 : 1.0)
                                        .animation(.spring(), value: isTodayDone)
                                    
                                    VStack(alignment: .leading) {
                                        Text("Daily Streak")
                                            .font(.subheadline)
                                            .foregroundColor(.gray)
                                        
                                        HStack(spacing: 6) {
                                            Text("\(dayStreak) Days")
                                                .font(.title2).bold()
                                            
                                            // Show the current status for the daily streak.
                                            let statusText = isTodayDone ? "• Done" : (isSessionInProgress ? "• In Progress (\(photoManager.sessionViewedCount)/\(photoManager.sessionTotalCount))" : "• To Do")
                                            
                                            Text(statusText)
                                                .font(.caption).bold()
                                                .foregroundColor(isTodayDone ? .green : (isSessionInProgress ? .orange : .gray))
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(
                                                    Capsule()
                                                        .fill(isTodayDone ? Color.green.opacity(0.1) : (isSessionInProgress ? Color.orange.opacity(0.1) : Color.gray.opacity(0.1)))
                                                )
                                        }
                                    }
                                    Spacer()
                                }
                                .padding()
                                .background(Color(.secondarySystemGroupedBackground))
                                .cornerRadius(16)
                            }
                            .padding(.horizontal, 24)
                            
                            Spacer()
                            
                            // Dynamic home buttons based on the current session state.

                            if photoManager.isLoading {
                                // Loading state shown on the home screen.
                                VStack(spacing: 12) {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .purple))
                                        .scaleEffect(1.5)
                                    
                                    // Use the loading message provided by the photo manager.
                                    Text(photoManager.loadingMessage)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundColor(.gray)
                                        .multilineTextAlignment(.center)
                                        .animation(.easeInOut, value: photoManager.loadingMessage)
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 80) // Reserve space so the interface does not jump.
                                .padding(.horizontal, 24)
                                .padding(.bottom, 40)
                                
                            } else {
                                // Buttons are shown only once loading is complete.
                                
                                if isSessionInProgress {
                                    // Case 1: a session is already in progress.
                                    VStack(spacing: 15) {
                                        Text("⏳ You have a session in progress")
                                            .font(.headline)
                                            .foregroundColor(.orange)
                                        
                                        Button(action: {
                                            currentSessionSavedMB = 0.0
                                            photoManager.checkPermissionAndFetch()
                                            withAnimation(.easeInOut) {
                                                isShowingSwipeView = true
                                            }
                                        }) {
                                            HStack {
                                                Text("Continue Today's Swipe")
                                                    .font(.headline)
                                                Image(systemName: "play.fill")
                                            }
                                            .foregroundColor(.white)
                                            .frame(maxWidth: .infinity)
                                            .frame(height: 56)
                                            .background(Color.orange)
                                            .cornerRadius(16)
                                        }
                                        
                                        // Optional manual reset for the current session.
                                        Button("Reset and start over") {
                                            photoManager.clearSessionState()
                                            photoManager.checkPermissionAndFetch()
                                        }
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                    }
                                    .padding(.horizontal, 24)
                                    .padding(.bottom, 40)
                                    
                                } else if isTodayDone {
                                    // Case 2: the day is already complete.
                                    VStack(spacing: 15) {
                                        Text("🎉 You're all caught up for today!")
                                            .font(.headline)
                                            .foregroundColor(.purple)
                                        
                                        Button(action: {
                                            photoManager.clearSessionState()
                                            swipeHistory.removeAll()
                                            photosToDelete.removeAll()
                                            currentSessionSavedMB = 0.0
                                            
                                            photoManager.checkPermissionAndFetch()
                                            withAnimation(.easeInOut) {
                                                isShowingSwipeView = true
                                            }
                                        }) {
                                            HStack {
                                                Text("Redo Today's Swipe")
                                                    .font(.headline)
                                                Image(systemName: "arrow.clockwise")
                                            }
                                            .foregroundColor(.white)
                                            .frame(maxWidth: .infinity)
                                            .frame(height: 56)
                                            .background(themeGradient)
                                            .cornerRadius(16)
                                        }
                                    }
                                    .padding(.horizontal, 24)
                                    .padding(.bottom, 40)
                                    
                                } else {
                                    // Case 3: start a new session.
                                    Button(action: {
                                        currentSessionSavedMB = 0.0
                                        withAnimation(.easeInOut) {
                                            isShowingSwipeView = true
                                        }
                                    }) {
                                        HStack {
                                            Text("Review Today's Memories")
                                                .font(.headline)
                                            Image(systemName: "arrow.right")
                                        }
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 56)
                                        .background(themeGradient)
                                        .cornerRadius(16)
                                    }
                                    .padding(.horizontal, 24)
                                    .padding(.bottom, 40)
                                }
                            }
                        }
                    }
                }
                
            }
            .fullScreenCover(item: $videoToPlay) { videoItem in
                FullScreenVideoPlayer(asset: videoItem.asset)
            }
            .sheet(isPresented: $isShowingSettings, onDismiss: {
                photoManager.checkPermissionAndFetch()
            }) {
                SettingsView()
            }
        }
    }
    
    // MARK: - Helper Methods
    
    /// Reverts the last swipe action (undo functionality).
    /// If a photo was deleted, removes it from the deletion queue and updates the saved size.
    /// Reinserts the photo at the front of the fetched items list.
    private func undoLastSwipe() {
        guard let lastAction = swipeHistory.popLast() else { return }
        withAnimation(.spring()) {
            if lastAction.wasDeleted {
                photosToDelete.removeAll(where: { $0.id == lastAction.photoItem.id })
                currentSessionSavedMB -= lastAction.size
            }
            photoManager.fetchedItems.insert(lastAction.photoItem, at: 0)
            // Remove the asset from the partially viewed IDs.
            photoManager.removeLastViewedAsset(id: lastAction.photoItem.asset.localIdentifier)
        }
    }
    
    /// Deletes selected photos and exits the swipe view while maintaining session state.
    /// Used when the user wants to save progress but continue the session later.
    /// Does not increment the daily streak (session is paused, not completed).
    private func emptyTrashPartiallyAndExit() {
        let assetsToDelete = photosToDelete.map { $0.asset }
        photoManager.deletePhotos(assets: assetsToDelete) { success in
            if success {
                totalMBReleased += currentSessionSavedMB
                photosToDelete.removeAll()
                swipeHistory.removeAll()
                currentSessionSavedMB = 0.0
                
                // Return to the home screen after saving the partial cleanup.
                withAnimation(.easeInOut) {
                    isShowingSwipeView = false
                }
                
                // Do not update the streak here, since the session is only paused.
                // Reload the list without the deleted items.
                photoManager.checkPermissionAndFetch()
            }
        }
    }
    
    /// Checks if today's date is new and updates the daily streak accordingly.
    /// Increments the streak counter and updates the last check date.
    /// Reschedules notifications when a day is completed.
    private func checkAndSetStreak() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let todayString = formatter.string(from: Date())
        
        if lastCheckDate != todayString {
            dayStreak += 1
            lastCheckDate = todayString
            
            // Update the notification reminder when the day is completed.
            // If notifications are enabled, tell the system that today's task is already done.
            if UserDefaults.standard.bool(forKey: "notificationsEnabled") {
                let savedTime = UserDefaults.standard.double(forKey: "notificationTime")
                NotificationManager.shared.scheduleDailyNotification(
                    at: Date(timeIntervalSince1970: savedTime),
                    isTodayDone: true
                )
            }
        }
    }
    
    /// Formats a duration in seconds into MM:SS format for display.
    /// - Parameter duration: Time interval in seconds.
    /// - Returns: Formatted string like "02:35" for 2 minutes 35 seconds.
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - Settings View

/// Settings view allowing users to configure app behavior and preferences.
/// Includes options for media type filtering, sort order, and daily reminders.
struct SettingsView: View {
    // MARK: - Environment
    
    /// Environment variable to dismiss this sheet.
    @Environment(\.dismiss) var dismiss
    
    // MARK: - Settings State
    
    /// Filter for media types: "Both", "Photos Only", or "Videos Only" (persisted).
    @AppStorage("mediaTypeFilter") private var mediaTypeFilter: String = "Both"
    /// Sort order for photos: "Oldest First", "Newest First", or "Random" (persisted).
    @AppStorage("sortOrder") private var sortOrder: String = "Oldest First"
    
    // MARK: - Notification Settings
    
    /// Whether daily reminder notifications are enabled (persisted).
    @AppStorage("notificationsEnabled") private var notificationsEnabled: Bool = false
    /// Time of day for the daily reminder notification (stored as time interval since 1970, persisted).
    @AppStorage("notificationTime") private var notificationTime: Double = Date().timeIntervalSince1970
    
    // MARK: - Available Options
    
    /// Array of available media type filter options.
    let mediaTypes = ["Both", "Photos Only", "Videos Only"]
    /// Array of available sort order options.
    let sortOrders = ["Oldest First", "Newest First", "Random"]
    
    // MARK: - Computed Properties
    
    /// Creates a binding to convert between stored time interval and Date for the time picker.
    /// - Returns: A Binding<Date> for use with the CustomDatePicker.
    private var selectedDate: Binding<Date> {
        Binding(
            get: { Date(timeIntervalSince1970: notificationTime) },
            set: { notificationTime = $0.timeIntervalSince1970 }
        )
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("What to review")) {
                    Picker("Media Type", selection: $mediaTypeFilter) {
                        ForEach(mediaTypes, id: \.self) { type in
                            Text(type)
                        }
                    }
                }
                
                Section(header: Text("Sort Order")) {
                    Picker("Order by", selection: $sortOrder) {
                        ForEach(sortOrders, id: \.self) { order in
                            Text(order)
                        }
                    }
                }
                
                // Notification settings section.
                Section(header: Text("Daily Reminder")) {
                    Toggle("Enable Reminders", isOn: $notificationsEnabled)
                        .onChange(of: notificationsEnabled) { oldValue, newValue in
                            handleNotificationToggle(enabled: newValue)
                        }
                        .tint(.purple)
                    
                    if notificationsEnabled {
                        HStack {
                            Spacer()
                            // Use the custom time picker with 15-minute intervals.
                            CustomDatePicker(selection: selectedDate, minuteInterval: 15)
                                .frame(height: 150)
                            Spacer()
                        }
                        .onChange(of: notificationTime) { oldValue, newValue in
                            // Update the notification when the selected time changes.
                            updateNotification()
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.bold)
                    .foregroundColor(.purple)
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    /// Handles the toggle of notifications on/off.
    /// Requests user permission if enabling, or cancels the notification if disabling.
    /// - Parameter enabled: Whether notifications should be enabled.
    private func handleNotificationToggle(enabled: Bool) {
        if enabled {
            NotificationManager.shared.requestAuthorization { granted in
                if granted {
                    updateNotification()
                } else {
                    // Disable the toggle if the user rejects system permissions.
                    notificationsEnabled = false
                }
            }
        } else {
            NotificationManager.shared.cancelNotification()
        }
    }
    
    /// Updates the scheduled notification with the current settings.
    /// Checks whether today's task is already completed before rescheduling.
    private func updateNotification() {
        // Check whether today is already completed before rescheduling the reminder.
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let lastCheckDate = UserDefaults.standard.string(forKey: "lastCheckDate") ?? ""
        let isTodayDone = lastCheckDate == formatter.string(from: Date())
        
        NotificationManager.shared.scheduleDailyNotification(
            at: Date(timeIntervalSince1970: notificationTime),
            isTodayDone: isTodayDone
        )
    }
}

// MARK: - Full Screen Video Player

/// Full-screen video player for displaying selected videos from the photo library.
/// Handles video loading from iCloud, playback controls, and progress indication.
struct FullScreenVideoPlayer: View {
    // MARK: - Properties
    
    /// The PHAsset video to display.
    let asset: PHAsset
    /// AVPlayer instance for video playback.
    @State private var player: AVPlayer?
    /// Environment variable to dismiss this view.
    @Environment(\.dismiss) var dismiss
    /// Message displayed during video loading (includes download progress).
    @State private var downloadProgressMessage: String = "Loading video..."
    
    var body: some View {
        // Handle the video layout and controls inside the full-screen view.
        ZStack {
            Color.black.ignoresSafeArea()
            
            // Video layer.
            if let player = player {
                VStack {
                    Spacer(minLength: 0)
                    
                    VideoPlayer(player: player)
                        .ignoresSafeArea()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    
                    Spacer(minLength: 0)
                }
                .ignoresSafeArea()
                .onAppear {
                    configureAudioSession()
                    player.play()
                }
                .onDisappear { player.pause() }
                .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { _ in
                    dismiss()
                }
            } else {
                // Loading screen while the video is being prepared.
                VStack(spacing: 20) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)
                    
                    Text(downloadProgressMessage)
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.8))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            
            // Overlay controls shown at the top of the screen.
            VStack {
                HStack {
                    // Add spacing on both sides so the close button stays centered.
                    Spacer()
                    
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.largeTitle)
                        // Use a softer color so the controls do not distract from the video.
                            .foregroundColor(.white.opacity(0.7))
                            .shadow(color: .black.opacity(0.3), radius: 5, x: 0, y: 3)
                            .padding(.top, 16) // Add space from the top edge of the device.
                    }
                    
                    Spacer()
                }
                // Push the control area upward within the layout.
                Spacer()
            }
            // Ensure the controls appear above the video content.
            .zIndex(1)
        }
        .onAppear(perform: loadVideo)
    }
    
    // MARK: - Private Methods
    
    /// Loads the video from the photo library.
    /// Handles iCloud download with progress updates.
    /// Initializes the AVPlayer once the video is ready.
    private func loadVideo() {
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        
        options.progressHandler = { progress, error, stop, info in
            DispatchQueue.main.async {
                self.downloadProgressMessage = "Downloading from iCloud (\(Int(progress * 100))%)..."
            }
        }
        
        PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { item, _ in
            DispatchQueue.main.async {
                if let item = item {
                    self.player = AVPlayer(playerItem: item)
                } else {
                    self.downloadProgressMessage = "Failed to load video"
                }
            }
        }
    }
    
    /// Configures the audio session for video playback.
    /// Sets the category to playback to allow audio during video playback.
    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Errore nella configurazione dell'Audio Session: \(error)")
        }
    }
}

// MARK: - Permission Denied View

/// View displayed when the user has denied or restricted access to their photo library.
/// Explains why photo access is needed and provides a button to open Settings.
struct PermissionDeniedView: View {
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "photo.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.red)
                .shadow(color: .red.opacity(0.3), radius: 10, x: 0, y: 5)
            
            Text("Photo Access Required")
                .font(.title).bold()
                .multilineTextAlignment(.center)
            
            Text("PhotoSwipe needs access to your photo library to help you review and clean up your memories. We respect your privacy and only process photos locally on your device.")
                .font(.body)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
            
            Button(action: {
                // Open the iOS settings screen directly for this app.
                if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsURL)
                }
            }) {
                Text("Open Settings")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Color.purple)
                    .cornerRadius(16)
                    .padding(.horizontal, 40)
                    .padding(.top, 20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }
}

#Preview {
    ContentView()
}
