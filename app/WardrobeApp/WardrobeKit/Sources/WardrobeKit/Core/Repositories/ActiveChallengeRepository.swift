import Foundation
import Observation

@MainActor
public protocol ActiveChallengeRepository {
    func load() -> ActiveChallenge?
    func save(_ challenge: ActiveChallenge)
    func clear()
    var didFailToPersist: Bool { get }
    func flush() async
}

@MainActor
@Observable
public final class FileActiveChallengeRepository {
    public private(set) var didFailToPersist = false

    private var cached: ActiveChallenge??
    private var isDirty = false
    private var writeTask: Task<Void, Never>?
    private let url: URL
    private let legacyDefaults: UserDefaults
    private static let legacyKey = "activeChallenge"

    private static let coalescingDelay = Duration.milliseconds(300)

    public init(directory: URL? = nil, legacyDefaults: UserDefaults = .standard) {
        url = (directory ?? URL.applicationSupportDirectory.appending(path: "Drafts"))
            .appending(path: "active-draft.json")
        self.legacyDefaults = legacyDefaults
    }

    public func load() -> ActiveChallenge? {
        if case let .some(value) = cached {
            return value
        }

        let value = readFromDisk() ?? adoptLegacyRecord()
        cached = .some(value)
        return value
    }

    public func save(_ challenge: ActiveChallenge) {
        write(challenge)
    }

    public func clear() {
        write(nil)
    }

    public func flush() async {
        guard let writeTask else { return }
        writeTask.cancel()
        await writeTask.value
    }

    private func write(_ challenge: ActiveChallenge?) {
        cached = .some(challenge)
        isDirty = true
        scheduleWrite()
    }

    private func scheduleWrite() {
        guard writeTask == nil else { return }

        writeTask = Task { [weak self] in
            try? await Task.sleep(for: Self.coalescingDelay)
            await self?.writePending()
        }
    }

    private func writePending() async {
        guard case let .some(value) = cached else { return }
        isDirty = false

        do {
            try await Self.persist(value, to: url)
            didFailToPersist = false
        } catch {
            Log.report(error)
            didFailToPersist = true
        }

        writeTask = nil
        if isDirty {
            scheduleWrite()
        }
    }

    private func readFromDisk() -> ActiveChallenge? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try JSONDecoder().decode(ActiveChallenge.self, from: data)
        } catch {
            Log.report(error)
            return nil
        }
    }

    private func adoptLegacyRecord() -> ActiveChallenge? {
        guard let data = legacyDefaults.data(forKey: Self.legacyKey) else { return nil }
        legacyDefaults.removeObject(forKey: Self.legacyKey)

        guard let challenge = try? JSONDecoder().decode(ActiveChallenge.self, from: data) else {
            Log.report(AppError.unexpected)
            return nil
        }
        write(challenge)
        return challenge
    }

    @concurrent
    private static func persist(_ challenge: ActiveChallenge?, to url: URL) async throws {
        guard let challenge else {
            try? FileManager.default.removeItem(at: url)
            return
        }

        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        var options: Data.WritingOptions = [.atomic]
        #if os(iOS)
            options.insert(.completeFileProtection) // §18.4, same as original captures
        #endif
        try JSONEncoder().encode(challenge).write(to: url, options: options)
    }
}

extension FileActiveChallengeRepository: ActiveChallengeRepository {}
