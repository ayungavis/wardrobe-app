//
//  WardrobeViewModel.swift
//  WardrobeKit
//
//  Created by Luisa Haning Tyas on 11/08/26.
//


import Foundation
import UIKit

@MainActor
final class WardrobeViewModel: ObservableObject {
    
    @Published var items: [ClothingItem] = []
    @Published var isScanning: Bool = false
    @Published var scanProgress: Double = 0.0 // 0.0 - 1.0
    @Published var processedPhotos: [ProcessedPhoto] = []
    
    private var processedPhotoIDs: Set<String> = []
    private let garmentSegmentation = GarmentSegmentationService()
    private let thumbnailStore = ThumbnailStore()
    
    func processSelectedPhotos(_ entries: [(id: String, image: UIImage)]) async {
        isScanning = true
        defer { isScanning = false }
        
        print("📸 Picker returned \(entries.count) total photo(s)")
        
        let newEntries = entries.filter { !processedPhotoIDs.contains($0.id) }
        let skippedCount = entries.count - newEntries.count

            print("✅ \(newEntries.count) new photo(s) to process")
            print("⏭️ \(skippedCount) photo(s) skipped — already processed before")
        
        let total = newEntries.count
        guard total > 0 else {
            print("🛑 Nothing new to process, stopping here")
                    return
            } // everything was already processed, nothing new to do

            for (index, entry) in newEntries.enumerated() {
                scanProgress = Double(index) / Double(total)
                print("⚙️ Processing photo \(index + 1)/\(total) — id: \(entry.id)")
            
                do {
                    guard let (classMap, uprightImage) = try garmentSegmentation.segment(entry.image) else {
                        print("⚠️ Segmentation returned nil for photo id: \(entry.id)")
                        continue
                    }
                    let cutouts = garmentSegmentation.cutoutAll(classMap: classMap, uprightImage: uprightImage)

                    if let cutout = cutouts[.top] {
                        items.append(makeClothingItem(category: "top", croppedImage: cutout))
                    }
                    if let cutout = cutouts[.bottom] {
                        items.append(makeClothingItem(category: "bottom", croppedImage: cutout))
                    }

                    processedPhotoIDs.insert(entry.id)
                    print("✅ Finished photo id: \(entry.id) — now marked as processed")
                    
            } catch {
                print("⚠️ Error processing photo \(index): \(error)")
                continue
            }
        }
        print("🏁 Done. Total processed IDs so far: \(processedPhotoIDs.count)")
        scanProgress = 1.0
    }
    
    private func makeClothingItem(category: String, croppedImage: UIImage) -> ClothingItem {
        let id = UUID()
        let path = thumbnailStore.save(croppedImage, id: id) ?? ""
        
        return ClothingItem(
            id: id,
            assetLocalIdentifier: "", // no longer tracking a specific PHAsset
            category: category,
            subcategory: "unclassified",
            dominantColor: nil,
            dateWorn: Date(),
            croppedThumbnailPath: path
        )
    }
}

