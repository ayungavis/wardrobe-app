import DesignSystem
import SwiftUI

struct EditorLoadFailedView: View {
    let error: AppError
    let onRetry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label {
                Text("common.errorTitle", bundle: .module)
            } icon: {
                Image(systemName: "photo.badge.exclamationmark")
            }
        } description: {
            Text(error.userMessage)
        } actions: {
            Button(action: onRetry) {
                Text("common.retry", bundle: .module)
            }
        }
    }
}
