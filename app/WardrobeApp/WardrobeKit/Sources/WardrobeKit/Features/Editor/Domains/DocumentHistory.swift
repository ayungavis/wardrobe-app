/// Session-scoped undo and redo for the canvas document (FR-088).
///
/// Snapshots rather than commands: every edit is already a whole-value mutation
/// of an `Equatable` struct, so a snapshot cannot drift from the operation that
/// produced it the way an inverse command can.
///
/// A value type with no view and no actor, so its rules are tested the same way
/// the document's own edits are.
///
/// **This never leaves the device.** PRD §18.1 puts the stack in local session
/// memory only, and §18.11–12 forbid editor text and drawing strokes — the
/// contents of every snapshot here — from reaching a log line or an analytics
/// event. Nothing in this type is encoded, uploaded, or interpolated into a
/// message.
struct DocumentHistory: Equatable {
    /// ponytail: the prototype's number. PRD §29 lists the retained-step
    /// ceiling as something still to be measured, so treat this as a step count
    /// and not a memory budget — copy-on-write keeps the real cost far below 50
    /// whole documents, because snapshots share the layer buffer until an edit
    /// forces one copy. Measure before trusting it.
    static let maximumSteps = 50

    private(set) var undoStack: [EditorDocument] = []
    private(set) var redoStack: [EditorDocument] = []

    var canUndo: Bool {
        !undoStack.isEmpty
    }

    var canRedo: Bool {
        !redoStack.isEmpty
    }

    /// Records the state an edit is moving away from.
    ///
    /// Clearing redo is the point: a new edit makes any undone future
    /// unreachable, and keeping it would let redo jump to a document that never
    /// followed from this one.
    mutating func record(_ previous: EditorDocument) {
        undoStack.append(previous)
        if undoStack.count > Self.maximumSteps {
            undoStack.removeFirst(undoStack.count - Self.maximumSteps)
        }
        redoStack.removeAll(keepingCapacity: true)
    }

    mutating func undo(current: EditorDocument) -> EditorDocument? {
        guard let previous = undoStack.popLast() else { return nil }
        redoStack.append(current)
        return previous
    }

    /// Pushes back onto undo without clearing redo — walking forwards must
    /// leave the rest of the future reachable.
    mutating func redo(current: EditorDocument) -> EditorDocument? {
        guard let next = redoStack.popLast() else { return nil }
        undoStack.append(current)
        return next
    }
}
