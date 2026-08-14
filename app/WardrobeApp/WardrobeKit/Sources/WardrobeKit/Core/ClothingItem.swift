//
//  ClothingItem.swift
//  WardrobeKit
//
//  Created by Luisa Haning Tyas on 11/08/26.
//


import Foundation
import UIKit

struct ClothingItem: Codable {
    let id: UUID
    let assetLocalIdentifier: String
    let category: String
    let subcategory: String
    let dominantColor: String?
    let dateWorn: Date
    let croppedThumbnailPath: String
}

struct ProcessedPhoto: Identifiable {
    let id: String          // PhotosPickerItem's itemIdentifier, a stable unique ID per photo
    let thumbnail: UIImage
}
