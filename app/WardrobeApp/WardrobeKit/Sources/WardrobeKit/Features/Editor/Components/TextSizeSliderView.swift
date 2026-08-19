import CoreGraphics
import DesignSystem
import SwiftUI

struct TextSizeSliderView: View {
    static let range: ClosedRange<CGFloat> = 0.5 ... 3

    @Binding var scale: CGFloat

    @State private var isDragging = false

    private let thumbDiameter: CGFloat = 26

    var body: some View {
        VStack(spacing: Spacing.sm) {
            Text(verbatim: "A")
                .font(.system(size: 17, weight: .bold))

            track

            Text(verbatim: "A")
                .font(.system(size: 10, weight: .bold))
        }
        .foregroundStyle(AppColor.onMedia)
        .padding(.vertical, Spacing.sm)
        .padding(.horizontal, Spacing.sm)
        .background(AppColor.mediaBackground.opacity(0.62), in: Capsule())
        .overlay {
            Capsule().stroke(AppColor.onMedia.opacity(0.12), lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("editor.text.size", bundle: .module))
        .accessibilityValue(Text(verbatim: "\(Int((scale * 100).rounded()))%"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: setScale(scale + 0.1)
            case .decrement: setScale(scale - 0.1)
            @unknown default: break
            }
        }
        .accessibilityIdentifier("editor.text.size")
    }

    private var track: some View {
        GeometryReader { proxy in
            let travel = max(proxy.size.height - thumbDiameter, 1)
            let progress = (scale - Self.range.lowerBound)
                / (Self.range.upperBound - Self.range.lowerBound)

            ZStack {
                Capsule()
                    .fill(AppColor.onMedia.opacity(0.30))
                    .frame(width: 4)
                    .padding(.vertical, thumbDiameter / 2)

                Circle()
                    .fill(AppColor.onMedia)
                    .frame(
                        width: isDragging ? 30 : thumbDiameter,
                        height: isDragging ? 30 : thumbDiameter
                    )
                    .overlay { Circle().stroke(AppColor.mediaBackground.opacity(0.16), lineWidth: 1) }
                    .shadow(color: AppColor.mediaBackground.opacity(0.28), radius: 5, y: 2)
                    .position(
                        x: proxy.size.width / 2,
                        y: thumbDiameter / 2 + (1 - progress) * travel
                    )
                    .animation(.snappy(duration: 0.16), value: isDragging)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { gesture in
                        if !isDragging {
                            EditorHaptics.commit.play()
                        }
                        isDragging = true
                        let offset = min(max(gesture.location.y - thumbDiameter / 2, 0), travel)
                        let newProgress = 1 - offset / travel
                        setScale(
                            Self.range.lowerBound
                                + newProgress * (Self.range.upperBound - Self.range.lowerBound)
                        )
                    }
                    .onEnded { _ in
                        EditorHaptics.selection.play()
                        isDragging = false
                    }
            )
        }
        .frame(width: 30)
    }

    private func setScale(_ value: CGFloat) {
        let clamped = min(max(value, Self.range.lowerBound), Self.range.upperBound)
        scale = (clamped * 20).rounded() / 20
    }
}
