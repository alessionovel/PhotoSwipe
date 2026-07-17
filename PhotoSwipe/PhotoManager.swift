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
    @Published var fetchedItems: [PhotoItem] = []
    @Published var authorizationStatus: PHAuthorizationStatus = .notDetermined
    @Published var isLoading: Bool = false
    
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
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            var itemsFound: [PhotoItem] = []
            
            let calendar = Calendar.current
            let todayComponents = calendar.dateComponents([.day, .month], from: Date())
            guard let targetDay = todayComponents.day, let targetMonth = todayComponents.month else { return }
            
            // 1. LEGGIAMO LE IMPOSTAZIONI DELL'UTENTE
            let mediaType = UserDefaults.standard.string(forKey: "mediaTypeFilter") ?? "Both"
            let sortOrder = UserDefaults.standard.string(forKey: "sortOrder") ?? "Oldest First"
            
            let fetchOptions = PHFetchOptions()
            
            // 2. APPLICHIAMO IL FILTRO PER FOTO/VIDEO
            if mediaType == "Photos Only" {
                fetchOptions.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
            } else if mediaType == "Videos Only" {
                fetchOptions.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.video.rawValue)
            } else {
                fetchOptions.predicate = NSPredicate(format: "mediaType == %d OR mediaType == %d", PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue)
            }
            
            // 3. APPLICHIAMO L'ORDINAMENTO BASE
            if sortOrder == "Oldest First" {
                fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
            } else {
                fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            }
            
            let allAssets = PHAsset.fetchAssets(with: fetchOptions)
            var validAssets: [PHAsset] = []
            
            allAssets.enumerateObjects { (asset, _, _) in
                if let creationDate = asset.creationDate {
                    let assetComponents = calendar.dateComponents([.day, .month], from: creationDate)
                    if assetComponents.day == targetDay && assetComponents.month == targetMonth {
                        validAssets.append(asset)
                    }
                }
            }
            
            // 4. SE L'UTENTE HA SCELTO RANDOM, MESCOLIAMO IL MAZZO!
            if sortOrder == "Random" {
                validAssets.shuffle()
            }
            
            let imageManager = PHImageManager.default()
            let requestOptions = PHImageRequestOptions()
            requestOptions.isNetworkAccessAllowed = true
            requestOptions.isSynchronous = true
            requestOptions.deliveryMode = .highQualityFormat
            
            // 5. CARICHIAMO FINO A 20 RICORDI PER SESSIONE (Aumentato il limite per godersi l'effetto Random)
            for asset in validAssets {
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
            }
        }
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
