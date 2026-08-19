import SwiftUI

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
