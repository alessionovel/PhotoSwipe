import Foundation
import Photos
import UIKit
import Combine

/// A model representing a single photo or video item from the photo library.
/// Conforms to `Identifiable` for use in SwiftUI views.
struct PhotoItem: Identifiable {
    /// Unique identifier for this photo/video item.
    let id = UUID()
    /// The thumbnail or display image of the photo/video.
    let image: UIImage
    /// Reference to the underlying PHAsset in the photo library.
    let asset: PHAsset
    /// Boolean flag indicating whether this item is a video (true) or photo (false).
    let isVideo: Bool
}

/// Manager class responsible for handling all photo library operations.
/// Handles permissions, fetching photos from the library, tracking viewing sessions,
/// and managing photo deletion. Conforms to `ObservableObject` for SwiftUI integration.
class PhotoManager: NSObject, ObservableObject {
    // MARK: - Published Properties
    // These properties trigger UI updates when changed.
    
    /// Array of photo items currently available for review in the swipe interface.
    @Published var fetchedItems: [PhotoItem] = []
    /// Current authorization status for accessing the photo library.
    @Published var authorizationStatus: PHAuthorizationStatus = .notDetermined
    /// Boolean indicating whether photos are currently being loaded from the library.
    @Published var isLoading: Bool = false
    /// Descriptive message shown to the user during the loading process.
    @Published var loadingMessage: String = "Searching memories..."
    
    // MARK: - Private Constants
    // UserDefaults keys for persisting session state across app launches.
    
    /// Key for storing whether a session is currently active.
    private let sessionInProgressKey = "sessionInProgress"
    /// Key for storing the list of asset IDs already viewed in the current session.
    private let viewedAssetIdsKey = "sessionViewedAssetIds"
    /// Key for storing the total count of photos available for the current session.
    private let sessionTotalCountKey = "sessionTotalCount"
    /// Key for storing the date when the current session started.
    private let sessionDateKey = "sessionDate"
    
    // MARK: - Session Tracking Properties
    
    /// Total number of photos available for review in the current session.
    /// Automatically persists to UserDefaults when changed.
    @Published var sessionTotalCount: Int = UserDefaults.standard.integer(forKey: "sessionTotalCount") {
        didSet {
            UserDefaults.standard.set(sessionTotalCount, forKey: sessionTotalCountKey)
        }
    }
    
    /// Computed property that returns the count of photos already viewed in the current session.
    /// - Returns: The number of unique asset IDs marked as viewed.
    var sessionViewedCount: Int {
        let viewedIds = UserDefaults.standard.stringArray(forKey: viewedAssetIdsKey) ?? []
        return viewedIds.count
    }
    
    // MARK: - Initialization
    
    /// Initializes the PhotoManager and immediately checks for photo library permissions.
    override init() {
        super.init()
        checkPermissionAndFetch()
    }
    
    // MARK: - Permission Management
    
    /// Requests authorization to access the user's photo library with read-write permissions.
    /// If permission is granted or limited, immediately fetches photos for today.
    func checkPermissionAndFetch() {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] status in
            DispatchQueue.main.async {
                self?.authorizationStatus = status
                if status == .authorized || status == .limited {
                    self?.fetchPhotosFromThisDayInPastYears()
                }
            }
        }
    }
    
    // MARK: - Photo Fetching
    
    /// Fetches all photos and videos from today's date (across all past years) from the photo library.
    /// Respects user settings for media type filtering and sort order.
    /// Excludes photos that were already viewed in the current session.
    /// Runs on a background thread to prevent UI blocking.
    func fetchPhotosFromThisDayInPastYears() {
        DispatchQueue.main.async {
                self.isLoading = true
                self.loadingMessage = "Searching your library..."
            }
            
            DispatchQueue.global(qos: .userInitiated).async {
                let calendar = Calendar.current
                
                // Create today's date string in yyyy-MM-dd format.
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                let todayString = formatter.string(from: Date())
                
                // Handle the case where the day has changed since the last session.
                let savedSessionDate = UserDefaults.standard.string(forKey: self.sessionDateKey) ?? ""
                
                if !savedSessionDate.isEmpty && savedSessionDate != todayString {
                    // Reset the previous day's session state when the date has changed.
                    UserDefaults.standard.set(false, forKey: self.sessionInProgressKey)
                    UserDefaults.standard.set([], forKey: self.viewedAssetIdsKey)
                    UserDefaults.standard.set(0, forKey: self.sessionTotalCountKey)
                    UserDefaults.standard.set(todayString, forKey: self.sessionDateKey)
                } else if savedSessionDate.isEmpty {
                    // Set today's date when no session has been started yet.
                    UserDefaults.standard.set(todayString, forKey: self.sessionDateKey)
                }

                var itemsFound: [PhotoItem] = []
                let todayComponents = calendar.dateComponents([.day, .month], from: Date())
                guard let targetDay = todayComponents.day, let targetMonth = todayComponents.month else { return }
                
                let mediaType = UserDefaults.standard.string(forKey: "mediaTypeFilter") ?? "Both"
                let sortOrder = UserDefaults.standard.string(forKey: "sortOrder") ?? "Oldest First"
                
                let viewedIds = UserDefaults.standard.stringArray(forKey: self.viewedAssetIdsKey) ?? []
                let isFirstStart = !UserDefaults.standard.bool(forKey: self.sessionInProgressKey)
                
                let fetchOptions = PHFetchOptions()
                // Keep the current media filter and sort order settings.
                if mediaType == "Photos Only" {
                    fetchOptions.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
                } else if mediaType == "Videos Only" {
                    fetchOptions.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.video.rawValue)
                } else {
                    fetchOptions.predicate = NSPredicate(format: "mediaType == %d OR mediaType == %d", PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue)
                }
                if sortOrder == "Oldest First" {
                    fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
                } else {
                    fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
                }
                
                let allAssets = PHAsset.fetchAssets(with: fetchOptions)
                var totalCountForToday = 0
                var validAssets: [PHAsset] = []
                
                allAssets.enumerateObjects { (asset, _, _) in
                    if let creationDate = asset.creationDate {
                        let assetComponents = calendar.dateComponents([.day, .month], from: creationDate)
                        if assetComponents.day == targetDay && assetComponents.month == targetMonth {
                            // Count all assets from the selected day.
                            totalCountForToday += 1
                            
                            // Exclude assets that were already viewed in the current session.
                            if !viewedIds.contains(asset.localIdentifier) {
                                validAssets.append(asset)
                            }
                        }
                    }
                }
                
                // Store the total number of items for a new session.
                if isFirstStart {
                    DispatchQueue.main.async {
                        self.sessionTotalCount = totalCountForToday
                        // Force the home view to refresh.
                        self.objectWillChange.send()
                    }
                } else {
                    // Refresh the UI when the app is restarted with an existing session.
                    DispatchQueue.main.async {
                        self.objectWillChange.send()
                    }
                }
                
                if sortOrder == "Random" {
                    validAssets.shuffle()
                }
                
                let imageManager = PHImageManager.default()
                let requestOptions = PHImageRequestOptions()
                requestOptions.isNetworkAccessAllowed = true
                requestOptions.isSynchronous = true
                requestOptions.deliveryMode = .highQualityFormat
                
                requestOptions.progressHandler = { progress, error, stop, info in
                    DispatchQueue.main.async {
                        self.loadingMessage = "Downloading from iCloud (\(Int(progress * 100))%)..."
                    }
                }
                
                for (index, asset) in validAssets.enumerated() {
                    DispatchQueue.main.async {
                        self.loadingMessage = "Loading memory \(index + 1) of \(validAssets.count)..."
                    }
                    
                    let targetSize = CGSize(width: 960, height: 1280)
                    imageManager.requestImage(for: asset, targetSize: targetSize, contentMode: .aspectFit, options: requestOptions) { (image, _) in
                        if let img = image {
                            let isVideo = asset.mediaType == .video
                            itemsFound.append(PhotoItem(image: img, asset: asset, isVideo: isVideo))
                        }
                    }
                }
                
                DispatchQueue.main.async {
                    self.fetchedItems = itemsFound
                    self.isLoading = false
                    self.loadingMessage = "Searching memories..."
                }
            }
        }
        
    // MARK: - Session State Management
    
    /// Marks a photo asset as viewed in the current session.
    /// Updates the viewed IDs list and marks the session as active.
    /// - Parameter id: The local identifier of the asset to mark as viewed.
    func markAssetAsViewed(id: String) {
        var viewedIds = UserDefaults.standard.stringArray(forKey: viewedAssetIdsKey) ?? []
        if !viewedIds.contains(id) {
            viewedIds.append(id)
            UserDefaults.standard.set(viewedIds, forKey: viewedAssetIdsKey)
        }
        UserDefaults.standard.set(true, forKey: sessionInProgressKey)
        
        // Save or confirm the current session date.
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        UserDefaults.standard.set(formatter.string(from: Date()), forKey: sessionDateKey)
        
        objectWillChange.send()
    }
        
    /// Removes an asset from the viewed list (used when undoing a swipe action).
    /// If no assets remain viewed, marks the session as inactive.
    /// - Parameter id: The local identifier of the asset to remove from viewed list.
    func removeLastViewedAsset(id: String) {
        var viewedIds = UserDefaults.standard.stringArray(forKey: viewedAssetIdsKey) ?? []
        viewedIds.removeAll(where: { $0 == id })
        UserDefaults.standard.set(viewedIds, forKey: viewedAssetIdsKey)
        if viewedIds.isEmpty {
            UserDefaults.standard.set(false, forKey: sessionInProgressKey)
        }
        objectWillChange.send()
    }
    
    /// Clears all session state, resetting the app to its initial state.
    /// Called when a session is completed or when the user manually resets the session.
    func clearSessionState() {
        UserDefaults.standard.set(false, forKey: sessionInProgressKey)
        UserDefaults.standard.set([], forKey: viewedAssetIdsKey)
        UserDefaults.standard.set(0, forKey: sessionTotalCountKey)
        UserDefaults.standard.set("", forKey: sessionDateKey) // Clear the session date once the session ends.
        objectWillChange.send()
    }
    
    // MARK: - Photo Information
    
    /// Calculates the file size of a photo or video asset in megabytes.
    /// - Parameter asset: The PHAsset to calculate the size for.
    /// - Returns: The size of the asset in MB.
    func getAssetSize(asset: PHAsset) -> Double {
        let resources = PHAssetResource.assetResources(for: asset)
        var totalSize: Int64 = 0
        for resource in resources {
            if let fileSize = resource.value(forKey: "fileSize") as? Int64 {
                totalSize += fileSize
            }
        }
        return Double(totalSize) / (1000.0 * 1000.0)
    }
    
    // MARK: - Photo Deletion
    
    /// Deletes the specified photo assets from the photo library.
    /// - Parameters:
    ///   - assets: Array of PHAsset objects to delete.
    ///   - completion: Closure called on the main thread with the success status of the deletion.
    func deletePhotos(assets: [PHAsset], completion: @escaping (Bool) -> Void) {
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.deleteAssets(assets as NSArray)
        }) { success, error in
            DispatchQueue.main.async {
                completion(success)
            }
        }
    }
}
