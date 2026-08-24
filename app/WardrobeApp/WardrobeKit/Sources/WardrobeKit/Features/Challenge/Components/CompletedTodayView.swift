import DesignSystem
import SwiftUI

public struct CompletedTodayView: View {
    //    @State private var isBulkScanPresented = false
    //    @State private var isCameraScanPresented = false
    //    @State private var viewModel: WardrobeViewModel
    //
    //    private let container: AppContainer
    let onAccept: (ChallengeCard) -> Void
    private static let freestyleCard = ChallengeCard(id: UUID(), prompt: "Freestyle")

    public var body: some View {
        VStack {
            FreestyleOutfitView(
                titleKey: "challenge.empty.freestyle.title",
                messageKey: "challenge.empty.freestyle.text",
                buttonKey: "challenge.accept",
                onAccept: {
                    print("Freestyle button tapped!")
                    onAccept(Self.freestyleCard)
                }
            )
            .aspectRatio(346 / 617, contentMode: .fit)
            .allowsHitTesting(true)

            Text("challenge.empty.text", bundle: .module)
                .font(AppFont.body.weight(.bold))
                .opacity(0.3)
            //            ContentUnavailableView {
//                Label {
//                    Text("challenge.completedToday.title", bundle: .module)
//                } icon: {
//                    Image(systemName: "checkmark.seal.fill")
//                }
//            } description: {
//                Text("challenge.completedToday.message", bundle: .module)
//            }
        }
    }
}
