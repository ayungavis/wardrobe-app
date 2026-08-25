import Foundation
import SwiftData

@MainActor
public protocol CursorStore: AnyObject {
    func position() throws -> Int64
    func stage(position: Int64) throws
    func commit() throws
    func discard()
}

// MARK: - SwiftData

@MainActor
public final class SwiftDataCursorStore: CursorStore {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    public func position() throws -> Int64 {
        try entity()?.position ?? 0
    }

    public func stage(position: Int64) throws {
        if let entity = try entity() {
            entity.position = position
        } else {
            context.insert(SyncCursorEntity(position: position))
        }
    }

    public func commit() throws {
        try context.save()
    }

    public func discard() {
        context.rollback()
    }

    private func entity() throws -> SyncCursorEntity? {
        try context.fetch(FetchDescriptor<SyncCursorEntity>()).first
    }
}

// MARK: - Storage entity

@Model
final class SyncCursorEntity {
    #Unique<SyncCursorEntity>([\.name])
    private(set) var name: String = "changes"
    var position: Int64 = 0

    init(position: Int64) {
        name = "changes"
        self.position = position
    }
}
