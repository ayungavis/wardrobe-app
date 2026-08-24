import DesignSystem
import SwiftUI

struct AppBackgroundImageView: View {
    var body: some View {
        Image("appBG", bundle: .module)
            .resizable()
            .ignoresSafeArea()
    }
}

extension View {
    func appBackgroundOnly() -> some View {
        background(AppBackgroundImageView())
    }
}
