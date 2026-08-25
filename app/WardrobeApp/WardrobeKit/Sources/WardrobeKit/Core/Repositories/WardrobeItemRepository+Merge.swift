import Foundation
import SwiftData

// MARK: - Merging two items (FR-026)

public extension SwiftDataWardrobeItemRepository {
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
