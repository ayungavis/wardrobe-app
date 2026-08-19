import Foundation

public struct WardrobeItem: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var description: String
    public var category: GarmentCategory
    public var status: ItemStatus
    public var cutoutFile: String
    public var illustrationURL: URL?
    public var styleVersion: String?
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String? = nil,
        description: String = "",
        category: GarmentCategory,
        status: ItemStatus = .pending,
        cutoutFile: String,
        illustrationURL: URL? = nil,
        styleVersion: String? = nil,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.name = name ?? category.defaultName
        self.description = description
        self.category = category
        self.status = status
        self.cutoutFile = cutoutFile
        self.illustrationURL = illustrationURL
        self.styleVersion = styleVersion
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public enum ItemStatus: String, CaseIterable, Codable, Sendable {
    case pending
    case processing
    case ready
    case failed
}
