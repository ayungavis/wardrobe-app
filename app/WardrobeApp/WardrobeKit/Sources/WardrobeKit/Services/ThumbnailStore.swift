//
//  ThumbnailStore.swift
//  WardrobeKit
//
//  Created by Luisa Haning Tyas on 11/08/26.
//


import UIKit

final class ThumbnailStore: @unchecked Sendable {

    private var directory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("ClothingThumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func save(_ image: UIImage, id: UUID) -> String? {
        guard let data = image.pngData() else { return nil }
        let fileURL = directory.appendingPathComponent("\(id.uuidString).png")
        do {
            try data.write(to: fileURL)
            return fileURL.path
        } catch {
            return nil
        }
    }
}
