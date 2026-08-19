import Foundation

/// Which layer a canvas gesture is allowed to act on.
///
/// Its own function rather than two clauses inside `body` because it is the one
/// genuinely new rule in an otherwise mechanical move of gesture ownership from
/// each layer up to the canvas — and the only part of that move a test can
/// reach.
enum EditorGesture {
    /// A press only latches a layer the canvas may actually transform.
    ///
    /// Refusing here rather than ignoring the gesture later is deliberate: an
    /// unheld layer lets the pinch fall through to nothing, which is what
    /// "locked keeps its geometry" should feel like (FR-086).
    static func canHold(_ layer: EditorLayer, activeTool: EditorViewModel.Tool?) -> Bool {
        // A tool owns the canvas while it is open. The drawing surface in
        // particular is mounted above the layers so a stroke drawn across a
        // sticker draws instead of dragging it — and the canvas gesture sits
        // further out still, so without this it would take that back.
        guard activeTool == nil else { return false }
        return !layer.isLocked
    }

    /// Which layer a press should leave held. **The first finger down wins:**
    /// while one layer is held, a second finger landing on another must not
    /// take the gesture with it — the user is still holding the first.
    static func hold(
        current: UUID?,
        pressing layer: EditorLayer,
        activeTool: EditorViewModel.Tool?
    ) -> UUID? {
        guard current == nil else { return current }
        return canHold(layer, activeTool: activeTool) ? layer.id : nil
    }

    /// For the same reason, a tap must not move the selection while a layer is
    /// being held — the second finger is part of the gesture, not a new choice.
    static func canSelect(_ id: UUID, whileHolding held: UUID?) -> Bool {
        held == nil || held == id
    }
}
