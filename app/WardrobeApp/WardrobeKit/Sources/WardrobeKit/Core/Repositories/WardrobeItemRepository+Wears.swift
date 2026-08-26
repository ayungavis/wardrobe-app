import Foundation
import SwiftData

// MARK: - Wear records

extension SwiftDataWardrobeItemRepository {
    func stageInsert(wear: WearRecord) {
        context.insert(WearRecordEntity(wear))
    }

    func stageApply(wear: WearRecord, deletedAt: Date?) throws {
        let wearID = wear.id
        let existing = try context.fetch(
            FetchDescriptor<WearRecordEntity>(predicate: #Predicate { $0.id == wearID })
        ).first
        if deletedAt != nil {
            if let existing {
                context.delete(existing)
            }
            return
        }
        if let existing {
            existing.itemID = wear.itemID
            existing.completionID = wear.completionID
            if !calendar.isDate(existing.wornAt, inSameDayAs: wear.wornAt) {
                existing.wornAt = wear.wornAt
            }
            return
        }
        context.insert(WearRecordEntity(wear))
    }
}
