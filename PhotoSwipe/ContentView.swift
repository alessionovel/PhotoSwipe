import SwiftUI
import Photos
import AVKit

struct SwipedAction {
    let photoItem: PhotoItem
    let wasDeleted: Bool
    let size: Double
}

struct VideoToPlay: Identifiable {
    let id = UUID()
    let asset: PHAsset
}

struct ContentView: View {
    @StateObject private var photoManager = PhotoManager()
    @State private var offset: CGSize = .zero
    
    @State private var swipeHistory: [SwipedAction] = []
    @State private var photosToDelete: [PhotoItem] = []
    
    @State private var currentSessionSavedMB: Double = 0.0
    
    @AppStorage("totalMBReleased") private var totalMBReleased: Double = 0.0
    @AppStorage("dayStreak") private var dayStreak: Int = 0
    @AppStorage("lastCheckDate") private var lastCheckDate: String = ""
    
    @State private var isShowingSwipeView = false
    @State private var videoToPlay: VideoToPlay? = nil
    
    @State private var isShowingSettings = false
    
    let themeGradient = LinearGradient(colors: [.purple, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing)
    
    private var isTodayDone: Bool {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return lastCheckDate == formatter.string(from: Date())
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()
                
                if isShowingSwipeView {
                    VStack {
                        // BARRA DI NAVIGAZIONE SUPERIORE
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
                        
                        // --- NUOVA BARRA DI PROGRESSO ---
                        if !photoManager.isLoading {
                            let totalItems = photoManager.fetchedItems.count + swipeHistory.count
                            // La mostriamo solo se c'è almeno un elemento nella sessione
                            if totalItems > 0 {
                                VStack(spacing: 8) {
                                    let itemsDone = photoManager.fetchedItems.isEmpty ? totalItems : swipeHistory.count
                                    
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
                            VStack(spacing: 25) {
                                ProgressView()
                                    .scaleEffect(1.5)
                                    .tint(.purple)
                                Text("Fetching memories...")
                                    .font(.headline)
                                    .foregroundColor(.gray)
                            }
                            
                        } else if let currentItem = photoManager.fetchedItems.first {
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
                                                }
                                                offset = .zero
                                            }
                                        } else {
                                            withAnimation(.spring()) { offset = .zero }
                                        }
                                    }
                            )
                                
                        } else if !photosToDelete.isEmpty {
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
                                            checkAndSetStreak()
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
                                checkAndSetStreak()
                            }
                        }
                        Spacer()
                    }
                } else {
                    VStack(spacing: 0) {
                        
                        HStack {
                            Spacer()
                            Button(action: {
                                isShowingSettings = true
                            }) {
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
                                    .foregroundColor(.orange)
                                    .frame(width: 50)
                                
                                VStack(alignment: .leading) {
                                    Text("Daily Streak")
                                        .font(.subheadline)
                                        .foregroundColor(.gray)
                                    Text("\(dayStreak) Days")
                                        .font(.title2).bold()
                                }
                                Spacer()
                            }
                            .padding()
                            .background(Color(.secondarySystemGroupedBackground))
                            .cornerRadius(16)
                        }
                        .padding(.horizontal, 24)
                        
                        Spacer()
                        
                        if isTodayDone {
                            VStack(spacing: 15) {
                                Text("🎉 You're all caught up for today!")
                                    .font(.headline)
                                    .foregroundColor(.purple)
                                
                                Button(action: {
                                    currentSessionSavedMB = 0.0
                                    photoManager.checkPermissionAndFetch()
                                    withAnimation(.easeInOut) {
                                        isShowingSwipeView = true
                                    }
                                }) {
                                    HStack {
                                        Text(photoManager.isLoading ? "Loading..." : "Redo Today's Swipe")
                                            .font(.headline)
                                        if !photoManager.isLoading {
                                            Image(systemName: "arrow.clockwise")
                                        } else {
                                            ProgressView()
                                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        }
                                    }
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 56)
                                    .background(photoManager.isLoading ? AnyShapeStyle(Color.purple.opacity(0.6)) : AnyShapeStyle(themeGradient))
                                    .cornerRadius(16)
                                }
                                .disabled(photoManager.isLoading)
                            }
                            .padding(.horizontal, 24)
                            .padding(.bottom, 40)
                            
                        } else {
                            Button(action: {
                                currentSessionSavedMB = 0.0
                                withAnimation(.easeInOut) {
                                    isShowingSwipeView = true
                                }
                            }) {
                                HStack {
                                    Text(photoManager.isLoading ? "Loading..." : "Review Today's Memories")
                                        .font(.headline)
                                    if !photoManager.isLoading {
                                        Image(systemName: "arrow.right")
                                    } else {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    }
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                                .background(photoManager.isLoading ? AnyShapeStyle(Color.purple.opacity(0.6)) : AnyShapeStyle(themeGradient))
                                .cornerRadius(16)
                            }
                            .disabled(photoManager.isLoading)
                            .padding(.horizontal, 24)
                            .padding(.bottom, 40)
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
    
    private func undoLastSwipe() {
        guard let lastAction = swipeHistory.popLast() else { return }
        withAnimation(.spring()) {
            if lastAction.wasDeleted {
                photosToDelete.removeAll(where: { $0.id == lastAction.photoItem.id })
                currentSessionSavedMB -= lastAction.size
            }
            photoManager.fetchedItems.insert(lastAction.photoItem, at: 0)
        }
    }
    
    private func checkAndSetStreak() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let todayString = formatter.string(from: Date())
        
        if lastCheckDate != todayString {
            dayStreak += 1
            lastCheckDate = todayString
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    
    @AppStorage("mediaTypeFilter") private var mediaTypeFilter: String = "Both"
    @AppStorage("sortOrder") private var sortOrder: String = "Oldest First"
    
    let mediaTypes = ["Both", "Photos Only", "Videos Only"]
    let sortOrders = ["Oldest First", "Newest First", "Random"]
    
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
}

struct FullScreenVideoPlayer: View {
    let asset: PHAsset
    @State private var player: AVPlayer?
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            
            if let player = player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
                    .onAppear { player.play() }
                    .onDisappear { player.pause() }
                    .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { _ in
                        dismiss()
                    }
            } else {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            
            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.largeTitle)
                    .foregroundColor(.white.opacity(0.8))
                    .padding()
            }
        }
        .onAppear(perform: loadVideo)
    }
    
    private func loadVideo() {
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        
        PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { item, _ in
            DispatchQueue.main.async {
                if let item = item {
                    self.player = AVPlayer(playerItem: item)
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
