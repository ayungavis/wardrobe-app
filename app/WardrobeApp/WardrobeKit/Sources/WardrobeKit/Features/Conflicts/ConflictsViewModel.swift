import Foundation
import Observation

@MainActor
@Observable
public final class ConflictsViewModel {
    public struct ItemConflictDisplay: Identifiable, Equatable {
        public let conflict: ItemConflict
        public let itemName: String
        public let currentValue: String?

        public var id: UUID {
            conflict.id
        }
    }

    public struct CompletionDayConflict: Identifiable, Equatable {
        public let day: Date
        public let completions: [CompletedChallenge]

        public var id: Date {
            day
        }
    }

    private(set) var itemConflicts: [ItemConflictDisplay] = []
    private(set) var completionConflicts: [CompletionDayConflict] = []

    private let wardrobe: WardrobeItemRepository
    private let completions: CompletedChallengeRepository
    private let outbox: any OutboxRepository
    private let previews: CompletionPreviewRepository?
    private let syncNow: () async -> Void
    private(set) var syncTask: Task<Void, Never>?
    private let calendar: Calendar

    public init(
        wardrobe: WardrobeItemRepository,
        completions: CompletedChallengeRepository,
        outbox: any OutboxRepository,
        previews: CompletionPreviewRepository? = nil,
        syncNow: @escaping () async -> Void = {},
        calendar: Calendar = .current
    ) {
        self.wardrobe = wardrobe
        self.completions = completions
        self.outbox = outbox
        self.previews = previews
        self.syncNow = syncNow
        self.calendar = calendar
    }

    public var isEmpty: Bool {
        itemConflicts.isEmpty && completionConflicts.isEmpty
    }

    public func load() {
        let items = (try? wardrobe.items()) ?? []
        let names = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        itemConflicts = ((try? wardrobe.openConflicts()) ?? []).map { conflict in
            ItemConflictDisplay(
                conflict: conflict,
                itemName: names[conflict.itemID]?.name ?? "",
                currentValue: currentValue(of: conflict, in: names[conflict.itemID])
            )
        }
        completionConflicts = conflictedDays(in: completions.load())
    }

    public func keepCurrent(_ display: ItemConflictDisplay) {
        resolve(display.conflict, choosing: .keepCurrent)
    }

    public func useIncoming(_ display: ItemConflictDisplay) {
        resolve(display.conflict, choosing: .useIncoming)
    }

    public func choose(_ winner: CompletedChallenge) throws {
        let stored = completions.load()
        let current = stored.first { $0.id == winner.id } ?? winner
        let contenders = stored.filter {
            $0.id != current.id && $0.status != .superseded
                && calendar.isDate($0.completedAt, inSameDayAs: current.completedAt)
        }
        guard current.status != .canonical || !contenders.isEmpty else { return }

        completions.stageStatus(id: current.id, status: .canonical)
        for other in contenders {
            completions.stageStatus(id: other.id, status: .superseded)
        }
        let mutation = SyncMutation.resolveCompletion(
            ResolveCompletionArgsDTO(completionId: current.id)
        )
        try outbox.stage(mutation.queued(), at: Date())
        try completions.commitStaged()
        Log.ui.info("Completion conflict resolved")
        push()
        load()
    }

    public func previewData(for completion: CompletedChallenge) -> Data? {
        guard let file = completion.previewFile else { return nil }
        return try? previews?.data(forFile: file)
    }

    private func resolve(_ conflict: ItemConflict, choosing choice: ConflictChoice) {
        do {
            try wardrobe.resolveConflict(conflict, choosing: choice)
            Log.ui.info("Item conflict resolved: \(conflict.field.rawValue, privacy: .public)")
            push()
        } catch {
            Log.report(error)
        }
        load()
    }

    private func push() {
        syncTask?.cancel()
        syncTask = Task { [syncNow] in await syncNow() }
    }

    private func currentValue(of conflict: ItemConflict, in item: WardrobeItem?) -> String? {
        guard let item else { return nil }
        switch conflict.field {
        case .name: return item.name
        case .category: return item.category.rawValue
        case .color, .garmentType: return nil
        }
    }

    private func conflictedDays(in stored: [CompletedChallenge]) -> [CompletionDayConflict] {
        let conflicted = stored.filter { $0.status == .conflicting && !$0.isDeliberateExtra }
        let days = Set(conflicted.map { calendar.startOfDay(for: $0.completedAt) })
        return days.sorted(by: >).map { day in
            CompletionDayConflict(
                day: day,
                completions: stored
                    .filter { calendar.isDate($0.completedAt, inSameDayAs: day) && $0.status != .superseded }
                    .sorted { $0.completedAt < $1.completedAt }
            )
        }
    }
}
