import DesignSystem
import SwiftUI

struct WeatherOptInView: View {
    let weather: any WeatherRepository

    @State private var permission: LocationPermission = .authorized
    @State private var isDismissed = false

    var body: some View {
        if permission == .notDetermined, !isDismissed {
            VStack(spacing: Spacing.sm) {
                Text("challenge.weather.prompt", bundle: .module)
                    .font(AppFont.caption)
                    .multilineTextAlignment(.center)

                HStack(spacing: Spacing.md) {
                    Button {
                        Task {
                            await weather.requestPermission()
                            permission = weather.permission
                            await weather.refresh(now: Date())
                        }
                    } label: {
                        Text("challenge.weather.enable", bundle: .module)
                    }

                    Button {
                        isDismissed = true
                    } label: {
                        Text("challenge.weather.notNow", bundle: .module)
                    }
                    .foregroundStyle(AppColor.textSecondary)
                }
                .font(AppFont.caption)
            }
            .padding(Spacing.md)
            .task { permission = weather.permission }
        }
    }
}
