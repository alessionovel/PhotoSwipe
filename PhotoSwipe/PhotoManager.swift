import Foundation
import Photos
import UIKit
import Combine

struct PhotoItem: Identifiable {
    let id = UUID()
    let image: UIImage
    let asset: PHAsset
    let isVideo: Bool
}

class PhotoManager: NSObject, ObservableObject {
    // ... le tue variabili esistenti ...
    @Published var fetchedItems: [PhotoItem] = []
    @Published var authorizationStatus: PHAuthorizationStatus = .notDetermined
    @Published var isLoading: Bool = false
    @Published var loadingMessage: String = "Searching memories..."
    
    // Chiavi per UserDefaults
    private let sessionInProgressKey = "sessionInProgress"
    private let viewedAssetIdsKey = "sessionViewedAssetIds"
    // NUOVA CHIAVE: Salva il totale iniziale della sessione
    private let sessionTotalCountKey = "sessionTotalCount"
    
    // NUOVA VARIABILE GENERATA CORRETTAMENTE
        @Published var sessionTotalCount: Int = UserDefaults.standard.integer(forKey: "sessionTotalCount") {
            didSet {
                UserDefaults.standard.set(sessionTotalCount, forKey: sessionTotalCountKey)
            }
        }
    
    // Calcoliamo quante foto sono già state completate (viste)
    var sessionViewedCount: Int {
        let viewedIds = UserDefaults.standard.stringArray(forKey: viewedAssetIdsKey) ?? []
        return viewedIds.count
    }
    
    override init() {
        super.init()
        checkPermissionAndFetch()
    }
    
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
    
    func fetchPhotosFromThisDayInPastYears() {
            DispatchQueue.main.async {
                self.isLoading = true
                self.loadingMessage = "Searching your library..."
            }
            
            DispatchQueue.global(qos: .userInitiated).async {
                var itemsFound: [PhotoItem] = []
                
                let calendar = Calendar.current
                let todayComponents = calendar.dateComponents([.day, .month], from: Date())
                guard let targetDay = todayComponents.day, let targetMonth = todayComponents.month else { return }
                
                let mediaType = UserDefaults.standard.string(forKey: "mediaTypeFilter") ?? "Both"
                let sortOrder = UserDefaults.standard.string(forKey: "sortOrder") ?? "Oldest First"
                
                let viewedIds = UserDefaults.standard.stringArray(forKey: self.viewedAssetIdsKey) ?? []
                let isFirstStart = !UserDefaults.standard.bool(forKey: self.sessionInProgressKey)
                
                let fetchOptions = PHFetchOptions()
                // ... (Mantieni i filtri multimediali e l'ordinamento intatti) ...
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
                            // Conteggio assoluto di TUTTI gli elementi del giorno
                            totalCountForToday += 1
                            
                            // Filtra per la sessione corrente
                            if !viewedIds.contains(asset.localIdentifier) {
                                validAssets.append(asset)
                            }
                        }
                    }
                }
                
                // Se è una nuova sessione, memorizziamo il totale assoluto del giorno
                            if isFirstStart {
                                DispatchQueue.main.async {
                                    self.sessionTotalCount = totalCountForToday
                                    // FORZA L'AGGIORNAMENTO DELLA HOME
                                    self.objectWillChange.send()
                                }
                            } else {
                                // Se invece è una sessione già avviata recuperata dal riavvio dell'app,
                                // forziamo comunque la Home a rinfrescarsi sul thread principale
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
        
        func markAssetAsViewed(id: String) {
            var viewedIds = UserDefaults.standard.stringArray(forKey: viewedAssetIdsKey) ?? []
            if !viewedIds.contains(id) {
                viewedIds.append(id)
                UserDefaults.standard.set(viewedIds, forKey: viewedAssetIdsKey)
            }
            UserDefaults.standard.set(true, forKey: sessionInProgressKey)
            // Forza l'aggiornamento della UI notificando il cambiamento di stato
            objectWillChange.send()
        }
        
        func removeLastViewedAsset(id: String) {
            var viewedIds = UserDefaults.standard.stringArray(forKey: viewedAssetIdsKey) ?? []
            viewedIds.removeAll(where: { $0 == id })
            UserDefaults.standard.set(viewedIds, forKey: viewedAssetIdsKey)
            if viewedIds.isEmpty {
                UserDefaults.standard.set(false, forKey: sessionInProgressKey)
            }
            objectWillChange.send()
        }
        
        func clearSessionState() {
            UserDefaults.standard.set(false, forKey: sessionInProgressKey)
            UserDefaults.standard.set([], forKey: viewedAssetIdsKey)
            UserDefaults.standard.set(0, forKey: sessionTotalCountKey)
            objectWillChange.send()
        }
    
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
