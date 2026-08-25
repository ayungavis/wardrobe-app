import Foundation

enum UndoHistoryPayload {
    // ponytail: an oversized history is dropped, never shipped and never a blocker
    // — holding the ✓ hostage for undo steps would break the daily loop that
    // FR-088 merely decorates.
    static func data(
        for steps: [EditorDocument],
        cap: Int = MediaKind.history.uploadCap
    ) -> Data? {
        guard !steps.isEmpty else { return nil }
        guard let encoded = try? JSONEncoder().encode(steps),
              let compressed = try? (encoded as NSData).compressed(using: .zlib) as Data,
              compressed.count <= cap
        else {
            Log.report(AppError.payloadTooLarge, context: Log.Context(operation: "history.encode"))
            return nil
        }
        return compressed
    }
}
