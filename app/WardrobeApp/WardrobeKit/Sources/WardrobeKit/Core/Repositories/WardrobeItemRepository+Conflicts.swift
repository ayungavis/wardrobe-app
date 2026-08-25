import Foundation
import SwiftData

// MARK: - The conflict ledger (FR-062)

extension SwiftDataWardrobeItemRepository {
    func stageApply(conflict: ItemConflict) throws {
        let conflictID = conflict.id
        let itemID = conflict.itemID
        let field = conflict.field.rawValue
        let revision = conflict.revision
        let siblings = try context.fetch(FetchDescriptor<ItemConflictEntity>(
            predicate: #Predicate { $0.itemID == itemID && $0.field == field && $0.revision == revision }
        ))
        guard !siblings.contains(where: { $0.id == conflictID || $0.value == conflict.value }) else {
            return
        }
        let entity = ItemConflictEntity(conflict)
        if try revision < localRev(of: conflict.field, itemID: itemID) {
            entity.resolvedAt = conflict.resolvedAt ?? Date()
        }
        context.insert(entity)
    }

    private func localRev(of field: ConflictField, itemID: UUID) throws -> Int64 {
        let entity = try context.fetch(
            FetchDescriptor<WardrobeItemEntity>(predicate: #Predicate { $0.id == itemID })
        ).first
        guard let entity else { return 0 }
        switch field {
        case .name: return entity.nameRev
        case .category: return entity.categoryRev
        case .color, .garmentType: return 0
        }
    }

    public func openConflicts() throws -> [ItemConflict] {
        let descriptor = FetchDescriptor<ItemConflictEntity>(
            predicate: #Predicate { $0.resolvedAt == nil },
            sortBy: [SortDescriptor(\.revision)]
        )
        return try context.fetch(descriptor).compactMap(\.domain)
    }

    public func resolveConflict(_ conflict: ItemConflict, choosing choice: ConflictChoice) throws {
        if choice == .useIncoming {
            try stage(.upsertItem(incomingArguments(for: conflict)))
        }
        let itemID = conflict.itemID
        let field = conflict.field.rawValue
        let open = try context.fetch(FetchDescriptor<ItemConflictEntity>(
            predicate: #Predicate { $0.itemID == itemID && $0.field == field && $0.resolvedAt == nil }
        ))
        let now = Date()
        for row in open {
            row.resolvedAt = now
        }
        try context.save()
    }

    private func incomingArguments(for conflict: ItemConflict) throws -> UpsertItemArgsDTO {
        let itemID = conflict.itemID
        let entity = try context.fetch(
            FetchDescriptor<WardrobeItemEntity>(predicate: #Predicate { $0.id == itemID })
        ).first
        var args = UpsertItemArgsDTO(id: conflict.itemID)
        switch conflict.field {
        case .name:
            let rev = max(entity?.nameRev ?? 0, conflict.revision) + 1
            if let entity, let value = conflict.value {
                entity.name = value
                entity.nameRev = rev
                entity.updatedAt = Date()
            }
            args.name = ItemFieldDTO(value: conflict.value, rev: rev)
        case .category:
            let rev = max(entity?.categoryRev ?? 0, conflict.revision) + 1
            if let entity, let value = conflict.value {
                entity.category = value
                entity.categoryRev = rev
                entity.updatedAt = Date()
            }
            args.category = ItemFieldDTO(value: conflict.value, rev: rev)
        case .color:
            args.color = ItemFieldDTO(value: conflict.value, rev: conflict.revision + 1)
        case .garmentType:
            args.garmentType = ItemFieldDTO(value: conflict.value, rev: conflict.revision + 1)
        }
        return args
    }
}

// MARK: - Storage entity

@Model
final class ItemConflictEntity {
    #Unique<ItemConflictEntity>([\.id])
    private(set) var id: UUID = UUID()
    var itemID: UUID = UUID()
    var field: String = ConflictField.name.rawValue
    var value: String?
    var revision: Int64 = 0
    var resolvedAt: Date?

    init(_ conflict: ItemConflict) {
        id = conflict.id
        itemID = conflict.itemID
        field = conflict.field.rawValue
        value = conflict.value
        revision = conflict.revision
        resolvedAt = conflict.resolvedAt
    }

    var domain: ItemConflict? {
        guard let field = ConflictField(rawValue: field) else { return nil }
        return ItemConflict(
            id: id, itemID: itemID, field: field, value: value,
            revision: revision, resolvedAt: resolvedAt
        )
    }
}
