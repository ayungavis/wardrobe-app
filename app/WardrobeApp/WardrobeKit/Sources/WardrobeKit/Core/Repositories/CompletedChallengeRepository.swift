import Foundation
import SwiftData

@MainActor
public protocol CompletedChallengeRepository: Sendable {
    func load() -> [CompletedChallenge]
    func append(_ completion: CompletedChallenge)
    func stage(_ completion: CompletedChallenge)
    func removeCompletions(on date: Date)
    func removeAll()
}

@MainActor
public extension CompletedChallengeRepository {
    func stage(_ completion: CompletedChallenge) {
        append(completion)
    }

    func hasCompletion(on date: Date, calendar: Calendar = .current) -> Bool {
        load().contains { calendar.isDate($0.completedAt, inSameDayAs: date) }
    }
}

// ponytail: UserDefaults JSON array; move to SwiftData when History needs
// querying and paging.
// Type safety: @unchecked because UserDefaults and Calendar are both immutable
// here and UserDefaults is itself thread-safe; the type holds no mutable state.
public final class UserDefaultsCompletedChallengeRepository: CompletedChallengeRepository, @unchecked Sendable {
    private let defaults: UserDefaults
    private let calendar: Calendar
    private static let key = "completedChallenges"

    public init(defaults: UserDefaults = .standard, calendar: Calendar = .current) {
        self.defaults = defaults
        self.calendar = calendar
    }

    // ponytail: a skipped entry is dropped rather than preserved verbatim.
    // Keeping its raw JSON needs a passthrough type; it comes back from the
    // server once sync exists, and the server is the system of record for
    // confirmed documents (FR-096).
    public func load() -> [CompletedChallenge] {
        guard let data = defaults.data(forKey: Self.key) else { return [] }
        guard let entries = try? JSONDecoder().decode([LenientEntry<CompletedChallenge>].self, from: data) else {
            Log.report(AppError.unexpected)
            return []
        }

        let completions = entries.compactMap(\.value)
        if completions.count != entries.count {
            Log.report(AppError.unexpected)
        }
        return completions
    }

    public func append(_ completion: CompletedChallenge) {
        var completions = load()
        completions.append(completion)
        save(completions)
    }

    public func removeCompletions(on date: Date) {
        let kept = load().filter { !calendar.isDate($0.completedAt, inSameDayAs: date) }
        save(kept)
    }

    public func removeAll() {
        defaults.removeObject(forKey: Self.key)
    }

    private func save(_ completions: [CompletedChallenge]) {
        guard let data = try? JSONEncoder().encode(completions) else {
            Log.report(AppError.unexpected)
            return
        }
        defaults.set(data, forKey: Self.key)
    }
}

private struct LenientEntry<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}

// MARK: - SwiftData

@MainActor
public final class SwiftDataCompletedChallengeRepository: CompletedChallengeRepository {
    private let context: ModelContext
    private let calendar: Calendar

    public init(context: ModelContext, calendar: Calendar = .current) {
        self.context = context
        self.calendar = calendar
    }

    public func load() -> [CompletedChallenge] {
        let descriptor = FetchDescriptor<CompletionEntity>(
            sortBy: [SortDescriptor(\.completedAt, order: .reverse)]
        )
        return ((try? context.fetch(descriptor)) ?? []).compactMap(\.domain)
    }

    public func append(_ completion: CompletedChallenge) {
        stage(completion)
        save()
    }

    public func stage(_ completion: CompletedChallenge) {
        guard let entity = CompletionEntity(completion) else {
            Log.report(AppError.unexpected)
            return
        }
        context.insert(entity)
    }

    public func removeCompletions(on date: Date) {
        for entity in stored() where calendar.isDate(entity.completedAt, inSameDayAs: date) {
            context.delete(entity)
        }
        save()
    }

    public func removeAll() {
        try? context.delete(model: CompletionEntity.self)
        save()
    }

    private func stored() -> [CompletionEntity] {
        (try? context.fetch(FetchDescriptor<CompletionEntity>())) ?? []
    }

    private func save() {
        do {
            try context.save()
        } catch {
            Log.report(error)
        }
    }
}

// MARK: - Storage entity

@Model
final class CompletionEntity {
    #Unique<CompletionEntity>([\.id])
    private(set) var id: UUID = UUID()
    var photoID: UUID = UUID()
    var completedAt: Date = Date()
    var previewFile: String?
    var card: Data = Data()
    var document: Data = Data()

    init?(_ completion: CompletedChallenge) {
        guard let card = try? JSONEncoder().encode(completion.card),
              let document = try? JSONEncoder().encode(completion.document)
        else {
            return nil
        }
        id = completion.id
        photoID = completion.photoID
        completedAt = completion.completedAt
        previewFile = completion.previewFile
        self.card = card
        self.document = document
    }

    var domain: CompletedChallenge? {
        guard let card = try? JSONDecoder().decode(ChallengeCard.self, from: card),
              let document = try? JSONDecoder().decode(EditorDocument.self, from: document)
        else {
            return nil
        }
        return CompletedChallenge(
            id: id, card: card, photoID: photoID, document: document,
            completedAt: completedAt, previewFile: previewFile
        )
    }
}

// MARK: - Migration

// ponytail: the legacy key is dropped only after the write is read back and every
// id has arrived, so a write that fails can never take the old data with it.
@MainActor
@discardableResult
public func migrateCompletions(
    from legacy: any CompletedChallengeRepository,
    into store: any CompletedChallengeRepository,
    defaults: UserDefaults = .standard
) -> Int {
    let key = "completedChallenges.migratedToSwiftData"
    guard !defaults.bool(forKey: key) else { return 0 }

    let carried = legacy.load()
    guard !carried.isEmpty else {
        defaults.set(true, forKey: key)
        return 0
    }

    let existing = Set(store.load().map(\.id))
    for completion in carried where !existing.contains(completion.id) {
        store.append(completion)
    }

    let arrived = Set(store.load().map(\.id))
    guard carried.allSatisfy({ arrived.contains($0.id) }) else {
        Log.report(AppError.unexpected)
        return 0
    }

    legacy.removeAll()
    defaults.set(true, forKey: key)
    Log.app.info("Completions migrated: \(carried.count, privacy: .public)")
    return carried.count
}
