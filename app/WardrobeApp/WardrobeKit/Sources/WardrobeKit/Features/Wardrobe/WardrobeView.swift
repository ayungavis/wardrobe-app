import DesignSystem
import SwiftUI

public struct WardrobeView: View {
    public init() {}

    public var body: some View {
        NavigationStack {
            // PRD §17: empty state explains that completing the first
            // challenge creates wardrobe items.
            ContentUnavailableView {
                Label {
                    Text("wardrobe.empty.title", bundle: .module)
                } icon: {
                    Image(systemName: "tshirt")
                }
            } description: {
                Text("wardrobe.empty.message", bundle: .module)
            }
            .navigationTitle(Text("tab.wardrobe", bundle: .module))
        }
    }
}

#Preview {
    WardrobeView()
}
