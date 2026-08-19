//
//  HistoryViewModel.swift
//  WardrobeKit
//
//  Created by Luisa Haning Tyas on 17/08/26.
//

import Foundation
import Observation

@MainActor
@Observable
public final class HistoryViewModel {
    public private(set) var completions: [CompletedChallenge] = []

    private let completedRepository: CompletedChallengeRepository
    private let photoRepository: PhotoRepository
    private let wardrobeRepository: WardrobeItemRepository
    private let thumbnails: GarmentThumbnailRepository

    public init(
        completedRepository: CompletedChallengeRepository,
        photoRepository: PhotoRepository,
        wardrobeRepository: WardrobeItemRepository,
        thumbnails: GarmentThumbnailRepository
    ) {
        self.completedRepository = completedRepository
        self.photoRepository = photoRepository
        self.wardrobeRepository = wardrobeRepository
        self.thumbnails = thumbnails
    }

    public func load() {
        completions = completedRepository.load().sorted { $0.completedAt > $1.completedAt }
    }

    public func photoData(for completion: CompletedChallenge) -> Data? {
        try? photoRepository.loadOriginal(id: completion.photoID)
    }

    public func garmentsWorn(in completion: CompletedChallenge) -> [(item: WardrobeItem, wearCount: Int)] {
        do {
            let items = try wardrobeRepository.items()
            var results: [(WardrobeItem, Int)] = []

            for item in items {
                let wears = try wardrobeRepository.wears(for: item.id)
                let wasWornInThisCompletion = wears.contains { $0.completionID == completion.id }
                if wasWornInThisCompletion {
                    results.append((item, wears.count))
                }
            }
            return results
        } catch {
            Log.report(error)
            return []
        }
    }

    public func thumbnailData(for item: WardrobeItem) -> Data? {
        try? thumbnails.data(forFile: item.cutoutFile)
    }
}
