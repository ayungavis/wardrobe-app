import DesignSystem
import SwiftUI

struct WeatherSettingsView: View {
    let weather: any WeatherRepository

    @State private var permission: LocationPermission = .notDetermined

    var body: some View {
        Section {
            switch permission {
            case .notDetermined:
                Button {
                    Task {
                        await weather.requestPermission()
                        permission = weather.permission
                        await weather.refresh(now: Date())
                    }
                } label: {
                    Text("profile.weather.enable", bundle: .module)
                }
            case .denied:
                Text("profile.weather.denied", bundle: .module)
                    .font(AppFont.caption)
                #if os(iOS)
                    Button {
                        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                        UIApplication.shared.open(url)
                    } label: {
                        Text("profile.weather.openSettings", bundle: .module)
                    }
                #endif
            case .authorized:
                Text("profile.weather.on", bundle: .module)
                    .font(AppFont.caption)
            }
        } header: {
            Text("profile.weather.title", bundle: .module)
        } footer: {
            Link(destination: Self.attributionURL) {
                Text("profile.weather.attribution", bundle: .module)
                    .font(AppFont.caption)
            }
        }
        .task { permission = weather.permission }
    }

    private static let attributionURL = URL(
        string: "https://weatherkit.apple.com/legal-attribution.html"
    ) ?? URL(filePath: "/")
}
