import Foundation
import Observation

/// `@MainActor` rather than `Sendable`: the draft is held in memory between a
/// save and the disk write that follows it, and every caller — the editor, the
/// capture flow, the challenge deck — is already on the main actor. Isolating
/// the protocol is what lets that in-memory value need no lock.
@MainActor
public protocol ActiveChallengeRepository {
    func load() -> ActiveChallenge?
    /// Records the draft. The bytes may not have landed yet — see `flush()`.
    func save(_ challenge: ActiveChallenge)
    func clear()
    /// True when the last write did not land. The draft on screen and the draft
    /// on disk have diverged from that point, and silence is what made that
    /// invisible before (FR-004: "safely persisted").
    var didFailToPersist: Bool { get }
    /// Makes the most recent `save` durable.
    ///
    /// Exists because writes are coalesced: without a flush at the moments the
    /// app can stop — backgrounding, leaving the editor — a debounce would lose
    /// work that the previous write-through-on-every-gesture never could
    /// (FR-004: "the last safely persisted device-only draft").
    func flush() async
}

/// The in-progress draft (PRD §18.3 — device only until ✓).
///
/// A file rather than `UserDefaults`: the draft carries every point of every
/// drawing stroke and has no settled size ceiling, and `UserDefaults` is a
/// preferences store that the system loads whole. Its own file also makes the
/// two lifetimes physical — whatever uploads confirmed documents later has
/// nothing here to reach for.
///
/// One file, no key. There is only ever one active challenge, so the running
/// draft is identified by that and needs no hash of the photo.
@MainActor
@Observable
public final class FileActiveChallengeRepository {
    /// `.some(nil)` means "read, and there is no draft" — distinct from "not
    /// read yet", which is what sends the first `load` to disk.
    public private(set) var didFailToPersist = false

    private var cached: ActiveChallenge??
    private var isDirty = false
    private var writeTask: Task<Void, Never>?
    private let url: URL
    private let legacyDefaults: UserDefaults
    private static let legacyKey = "activeChallenge"

    /// Long enough that a burst of edits becomes one write, short enough that
    /// it is over before a user can reach for the app switcher.
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
        // Cancelling here means "stop waiting", not "give up": the task treats
        // a cancelled sleep as its cue to write immediately.
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
            // Reported *and* surfaced: from here the draft on screen and the
            // draft on disk disagree, and a log line is not something the person
            // losing the work can read.
            Log.report(error)
            didFailToPersist = true
        }

        writeTask = nil
        // Anything saved while the disk write was in flight is newer than what
        // was written, so it needs a pass of its own.
        if isDirty {
            scheduleWrite()
        }
    }

    private func readFromDisk() -> ActiveChallenge? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try JSONDecoder().decode(ActiveChallenge.self, from: data)
        } catch {
            // A draft written by a newer app throws `documentFromNewerApp`, and
            // a silent nil would make an in-progress challenge look like it
            // never existed.
            Log.report(error)
            return nil
        }
    }

    /// Reads the draft one last time from where it used to live, then takes the
    /// key away. The same read-across `AccountPreferencesRepository` does for
    /// the old onboarding flag — without it, updating the app would throw away
    /// a challenge someone was in the middle of.
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

    /// Off the main actor: encoding a document with a drawing in it is real
    /// work, and it used to happen on every settled gesture with the canvas
    /// waiting for it.
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
