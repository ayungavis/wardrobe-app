import Foundation

struct WearHistoryGroup: Identifiable {
    let id = UUID()
    let title: String
    let entries: [WearHistoryEntry]
}

struct WearHistoryEntry: Identifiable {
    let id = UUID()
    let label: String
}
