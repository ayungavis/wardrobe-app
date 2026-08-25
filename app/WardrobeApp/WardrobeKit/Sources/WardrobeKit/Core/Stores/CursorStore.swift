import Foundation
import SwiftData

@MainActor
public protocol CursorStore: AnyObject {
    func position() throws -> Int64
    func stage(position: Int64) throws
    func commit() throws
    func discard()
    func reset() throws
    func align(interpretation version: Int) throws
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

    public func align(interpretation version: Int) throws {
        guard let entity = try entity() else {
            context.insert(SyncCursorEntity(position: 0, interpretation: version))
            try context.save()
            return
        }
        guard entity.interpretation != version else { return }
        entity.position = 0
        entity.interpretation = version
        try context.save()
    }

    public func reset() throws {
        try context.delete(model: SyncCursorEntity.self)
        try context.save()
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
    var interpretation: Int = 0

    init(position: Int64, interpretation: Int = 0) {
        name = "changes"
        self.position = position
        self.interpretation = interpretation
    }
}
