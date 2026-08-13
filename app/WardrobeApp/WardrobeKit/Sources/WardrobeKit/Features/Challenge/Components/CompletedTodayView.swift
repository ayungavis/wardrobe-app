import SwiftUI

/// PRD §17 "Completed today": the deck stays closed until the daily reset.
struct CompletedTodayView: View {
    var body: some View {
        ContentUnavailableView {
            Label {
                Text("challenge.completedToday.title", bundle: .module)
            } icon: {
                Image(systemName: "checkmark.seal.fill")
            }
        } description: {
            Text("challenge.completedToday.message", bundle: .module)
        }
    }
}
