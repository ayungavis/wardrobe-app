import DesignSystem
import SwiftUI

struct CaptureTimerButtonView: View {
    let timer: CaptureTimer
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if timer == .off {
                    Image(systemName: "timer")
                        .font(.system(size: 18, weight: .semibold))
                } else {
                    Text(timer.seconds, format: .number)
                        .font(AppFont.roundedTitle2)
                }
            }
            .foregroundStyle(AppColor.onMedia)
            .frame(width: 44, height: 44)
            .background {
                if timer == .off {
                    Circle().fill(.ultraThinMaterial).environment(\.colorScheme, .dark)
                } else {
                    Circle().fill(AppColor.accent)
                }
            }
        }
        .accessibilityLabel(Text("capture.camera.timer", bundle: .module))
        .accessibilityValue(value)
    }

    private var value: Text {
        guard timer != .off else { return Text("capture.camera.timer.off", bundle: .module) }
        return Text(Duration.seconds(timer.seconds), format: .units(allowed: [.seconds]))
    }
}
