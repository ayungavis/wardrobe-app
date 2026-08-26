import Foundation
import SwiftData

// MARK: - Merging two items (FR-026)

public extension SwiftDataWardrobeItemRepository {
    func adoptCutout(itemID: UUID, path: String, mediaID: UUID) throws {
        guard let entity = fetchItem(itemID) else { throw AppError.unexpected }
        entity.cutoutPath = path
        entity.updatedAt = Date()
        try stage(.upsertItem(UpsertItemArgsDTO(
            id: itemID,
            cutout: CutoutArgsDTO(id: UUID.v7(), mediaObjectId: mediaID, sourcePhotoId: nil)
        )))
        try context.save()
    }

    func deleteWears(completionID: UUID) throws {
        let descriptor = FetchDescriptor<WearRecordEntity>(
            predicate: #Predicate { $0.completionID == completionID }
        )
        for entity in try context.fetch(descriptor) {
            context.delete(entity)
        }
        try context.save()
    }

    func regenerateIllustration(itemID: UUID, note: String?) throws {
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        try stage(.regenerateIllustration(RegenerateIllustrationArgsDTO(
            itemId: itemID,
            note: trimmed?.isEmpty == false ? trimmed : nil
        )))
        if let entity = try context.fetch(
            FetchDescriptor<WardrobeItemEntity>(predicate: #Predicate { $0.id == itemID })
        ).first {
            entity.status = ItemStatus.pending.rawValue
        }
        try context.save()
    }

    func merge(winnerID: UUID, loserID: UUID) throws {
        guard winnerID != loserID else { throw AppError.unexpected }
        let loser = try context.fetch(
            FetchDescriptor<WardrobeItemEntity>(predicate: #Predicate { $0.id == loserID })
        ).first
        guard let loser, loser.deletedAt == nil else { return }

        for wear in try context.fetch(
            FetchDescriptor<WearRecordEntity>(predicate: #Predicate { $0.itemID == loserID })
        ) {
            wear.itemID = winnerID
        }
        for fingerprint in try context.fetch(
            FetchDescriptor<ItemFingerprintEntity>(predicate: #Predicate { $0.itemID == loserID })
        ) {
            fingerprint.itemID = winnerID
        }
        let now = Date()
        for conflict in try context.fetch(
            FetchDescriptor<ItemConflictEntity>(
                predicate: #Predicate { $0.itemID == loserID && $0.resolvedAt == nil }
            )
        ) {
            conflict.resolvedAt = now
        }
        loser.deletedAt = now

        try stage(.mergeItems(MergeItemsArgsDTO(winnerId: winnerID, loserId: loserID)))
        try context.save()
    }
}
