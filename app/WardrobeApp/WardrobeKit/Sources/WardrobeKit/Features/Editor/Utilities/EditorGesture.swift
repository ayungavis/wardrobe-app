import Foundation

enum EditorGesture {
    static func canHold(_ layer: EditorLayer, activeTool: EditorViewModel.Tool?) -> Bool {
        guard activeTool == nil else { return false }
        return !layer.isLocked
    }

    static func canSelect(_ id: UUID, whileHolding held: UUID?) -> Bool {
        held == nil || held == id
    }
}
