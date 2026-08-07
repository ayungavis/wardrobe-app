import DesignSystem
import SwiftUI

public struct HistoryView: View {
    public init() {}

    public var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label {
                    Text("history.empty.title", bundle: .module)
                } icon: {
                    Image(systemName: "photo.on.rectangle.angled")
                }
            } description: {
                Text("history.empty.message", bundle: .module)
            }
            .navigationTitle(Text("tab.history", bundle: .module))
        }
    }
}

#Preview {
    HistoryView()
}
