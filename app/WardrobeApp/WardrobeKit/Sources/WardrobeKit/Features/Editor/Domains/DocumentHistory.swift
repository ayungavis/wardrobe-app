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

    mutating func redo(current: EditorDocument) -> EditorDocument? {
        guard let next = redoStack.popLast() else { return nil }
        undoStack.append(current)
        return next
    }
}
