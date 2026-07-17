import SwiftUI
import Photos
import AVKit
import AVFoundation

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
    
    // NUOVO: Tiene traccia se c'è una sessione a metà lasciata in sospeso
    @AppStorage("sessionInProgress") private var isSessionInProgress: Bool = false
    
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
                            
                            // NUOVO PULSANTE: "FERMATI A METÀ" (Visibile solo se ci sono foto nel cestino temporaneo o elementi rimasti)
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
                        
                        // Barra di progresso (Inalterata)
                        if !photoManager.isLoading {
                                                    let totalItems = photoManager.sessionTotalCount
                                                    if totalItems > 0 {
                                                        VStack(spacing: 8) {
                                                            // Elementi fatti = quelli già registrati nel rullino + quelli temporanei di questa sessione attiva
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
                            // ... Schermata Caricamento (Inalterata) ...
                            VStack(spacing: 25) {
                                ProgressView()
                                    .scaleEffect(1.5)
                                    .tint(.purple)
                                Text(photoManager.loadingMessage)
                                    .font(.headline)
                                    .foregroundColor(.gray)
                            }
                        } else if let currentItem = photoManager.fetchedItems.first {
                            // --- SCHERMATA DI SWIPE ---
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
                                                    // MODIFICA: Salva l'elemento come visto
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
                                                    // MODIFICA: Salva l'elemento come visto
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
                            // --- SCHERMATA FINE SESSIONE STANDARD (Tutto il mazzo completato) ---
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
                                            photoManager.clearSessionState() // FINE SESSIONE COMPLETA: Resetta lo stato parziale
                                            checkAndSetStreak() // ASSEGNA STREAK COMPLETA
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
                                photoManager.clearSessionState() // Fine sessione senza eliminazioni rimaste
                                checkAndSetStreak()
                            }
                        }
                        Spacer()
                    }
                } else {
                    // --- SCHERMATA HOME PRINCIPALE ---
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
                        
                        // Statistiche (Spazio salvato e Streak)
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
                                                                // Se oggi è completato mostra il colore arancione, altrimenti grigio
                                                                .foregroundColor(isTodayDone ? .orange : Color(.systemGray3))
                                                                .frame(width: 50)
                                                                // Un piccolo effetto di scala per far risaltare il fuoco quando è attivo
                                                                .scaleEffect(isTodayDone ? 1.1 : 1.0)
                                                                .animation(.spring(), value: isTodayDone)
                                                            
                                                            VStack(alignment: .leading) {
                                                                Text("Daily Streak")
                                                                    .font(.subheadline)
                                                                    .foregroundColor(.gray)
                                                                
                                                                HStack(spacing: 6) {
                                                                                                        Text("\(dayStreak) Days")
                                                                                                            .font(.title2).bold()
                                                                                                        
                                                                                                        // Mostra il progresso effettivo es. "In Progress (5/20)"
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
                        
                        // --- LOGICA BOTTONI DINAMICI IN HOME ---
                        if isSessionInProgress {
                            // CASO 1: SESSIONE IN CORSO (PAUSA A METÀ)
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
                                        Text(photoManager.isLoading ? "Loading..." : "Continue Today's Swipe")
                                            .font(.headline)
                                        if !photoManager.isLoading {
                                            Image(systemName: "play.fill")
                                        } else {
                                            ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        }
                                    }
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 56)
                                    .background(photoManager.isLoading ? AnyShapeStyle(Color.orange.opacity(0.6)) : AnyShapeStyle(Color.orange))
                                    .cornerRadius(16)
                                }
                                .disabled(photoManager.isLoading)
                                
                                // Reset manuale opzionale
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
                                                    // CASO 2: GIORNATA COMPLETATA
                                                    VStack(spacing: 15) {
                                                        Text("🎉 You're all caught up for today!")
                                                            .font(.headline)
                                                            .foregroundColor(.purple)
                                                        
                                                        Button(action: {
                                                            // --- SOLUZIONE DEL BUG QUI ---
                                                            photoManager.clearSessionState() // Resetta la sessione precedente prima del redo!
                                                            swipeHistory.removeAll()         // Svuota la cronologia locale degli swipe
                                                            photosToDelete.removeAll()       // Svuota eventuali residui nel cestino
                                                            currentSessionSavedMB = 0.0      // Azzera i MB della sessione
                                                            
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
                                                                    ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white))
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
                            // CASO 3: NUOVA SESSIONE DA INIZIARE
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
                                        ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white))
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
            // MODIFICA: Rimuovi dagli ID visti parziali
            photoManager.removeLastViewedAsset(id: lastAction.photoItem.asset.localIdentifier)
        }
    }
    
    // NUOVA FUNZIONE: Elimina quello che c'è finora nel cestino, chiude la schermata e imposta lo stato "continua"
    private func emptyTrashPartiallyAndExit() {
        let assetsToDelete = photosToDelete.map { $0.asset }
        photoManager.deletePhotos(assets: assetsToDelete) { success in
            if success {
                totalMBReleased += currentSessionSavedMB
                photosToDelete.removeAll()
                swipeHistory.removeAll()
                currentSessionSavedMB = 0.0
                
                // Chiude la schermata di swipe tornando alla Home
                withAnimation(.easeInOut) {
                    isShowingSwipeView = false
                }
                
                // IMPORTANTE: NON chiama checkAndSetStreak(), quindi NON assegna la streak giornaliera!
                // Ricarica la lista escludendo le foto eliminate
                photoManager.checkPermissionAndFetch()
            }
        }
    }
    
    private func checkAndSetStreak() {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            let todayString = formatter.string(from: Date())
            
            if lastCheckDate != todayString {
                dayStreak += 1
                lastCheckDate = todayString
                
                // --- AGGIORNAMENTO NOTIFICA ---
                // Se le notifiche sono attive, ricalcoliamo il reminder dicendo al sistema
                // che per oggi il compito è già stato assolto
                if UserDefaults.standard.bool(forKey: "notificationsEnabled") {
                    let savedTime = UserDefaults.standard.double(forKey: "notificationTime")
                    NotificationManager.shared.scheduleDailyNotification(
                        at: Date(timeIntervalSince1970: savedTime),
                        isTodayDone: true
                    )
                }
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
    
    // NUOVI STATI PER LE NOTIFICHE
    @AppStorage("notificationsEnabled") private var notificationsEnabled: Bool = false
    @AppStorage("notificationTime") private var notificationTime: Double = Date().timeIntervalSince1970
    
    let mediaTypes = ["Both", "Photos Only", "Videos Only"]
    let sortOrders = ["Oldest First", "Newest First", "Random"]
    
    // Helper per convertire il Double di AppStorage in una Date di Swift
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
                
                // NUOVA SEZIONE NOTIFICHE
                Section(header: Text("Daily Reminder")) {
                    Toggle("Enable Reminders", isOn: $notificationsEnabled)
                        .onChange(of: notificationsEnabled) { oldValue, newValue in
                            handleNotificationToggle(enabled: newValue)
                        }
                        .tint(.purple)
                    
                    if notificationsEnabled {
                                            HStack {
                                                Spacer()
                                                // USIAMO IL NUOVO COMPONENTE CON INTERVALLO A 15 MINUTI
                                                CustomDatePicker(selection: selectedDate, minuteInterval: 15)
                                                    .frame(height: 150)
                                                Spacer()
                                            }
                                            .onChange(of: notificationTime) { oldValue, newValue in
                                                // Ora questo invia semplicemente l'aggiornamento,
                                                // senza bisogno di fare calcoli o arrotondamenti!
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
    
    private func handleNotificationToggle(enabled: Bool) {
        if enabled {
            NotificationManager.shared.requestAuthorization { granted in
                if granted {
                    updateNotification()
                } else {
                    // Se l'utente rifiuta i permessi a livello di sistema, spegniamo il toggle
                    notificationsEnabled = false
                }
            }
        } else {
            NotificationManager.shared.cancelNotification()
        }
    }
    
    private func updateNotification() {
        // Recuperiamo lo stato odierno per capire se saltare la notifica di oggi
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

struct FullScreenVideoPlayer: View {
    let asset: PHAsset
    @State private var player: AVPlayer?
    @Environment(\.dismiss) var dismiss
    @State private var downloadProgressMessage: String = "Loading video..."
    
    var body: some View {
        // Rimuoviamo l'allineamento globale topTrailing dallo ZStack per gestirlo internamente
        ZStack {
            Color.black.ignoresSafeArea()
            
            // --- LIVELLO DEL VIDEO ---
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
                // Schermata di caricamento/download
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
            
            // --- LIVELLO DEI CONTROLLI (In alto) ---
            VStack {
                HStack {
                    // Spacer a sinistra e destra per forzare la X al centro
                    Spacer()
                    
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.largeTitle)
                            // Un colore leggermente meno contrastato per non disturbare troppo la visione
                            .foregroundColor(.white.opacity(0.7))
                            .shadow(color: .black.opacity(0.3), radius: 5, x: 0, y: 3)
                            .padding(.top, 16) // Spazio dal bordo superiore del dispositivo
                    }
                    
                    Spacer()
                }
                // Spingiamo tutto il contenuto dell'HStack verso l'alto
                Spacer()
            }
            // Assicuriamo che i controlli siano sopra al video
            .zIndex(1)
        }
        .onAppear(perform: loadVideo)
    }
    
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
    
    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Errore nella configurazione dell'Audio Session: \(error)")
        }
    }
}

#Preview {
    ContentView()
}
