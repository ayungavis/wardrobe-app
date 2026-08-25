import Foundation

public enum ConflictField: String, Sendable, CaseIterable {
    case name
    case color
    case garmentType = "garment_type"
    case category

    public var label: String {
        switch self {
        case .name: String(localized: "conflicts.field.name", bundle: .module)
        case .color: String(localized: "conflicts.field.color", bundle: .module)
        case .garmentType: String(localized: "conflicts.field.garmentType", bundle: .module)
        case .category: String(localized: "conflicts.field.category", bundle: .module)
        }
    }
}

public enum ConflictChoice: Sendable, Equatable {
    case keepCurrent
    case useIncoming
}

public struct ItemConflict: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let itemID: UUID
    public let field: ConflictField
    public let value: String?
    public let revision: Int64
    public let resolvedAt: Date?

    public init(
        id: UUID,
        itemID: UUID,
        field: ConflictField,
        value: String?,
        revision: Int64,
        resolvedAt: Date? = nil
    ) {
        self.id = id
        self.itemID = itemID
        self.field = field
        self.value = value
        self.revision = revision
        self.resolvedAt = resolvedAt
    }
}
