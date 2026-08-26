import DesignSystem
import SwiftUI

struct CameraViewfinderView<Model: CameraStageModel>: View {
    let model: Model

    @State private var viewfinderSize: CGSize = .zero
    @State private var zoomStartValue: CGFloat?
    @State private var focusIndicator: FocusIndicator?

    private struct FocusIndicator: Equatable, Identifiable {
        let id = UUID()
        let point: CGPoint
    }

    var body: some View {
        viewfinder
            .onGeometryChange(for: CGSize.self) { proxy in
                proxy.size
            } action: { newSize in
                viewfinderSize = newSize
            }
            .gesture(focusTapGesture)
            .simultaneousGesture(zoomGesture)
            .overlay { focusSquare }
    }

    @ViewBuilder
    private var viewfinder: some View {
        if let session = model.previewSession {
            #if os(iOS)
                CameraPreviewView(session: session)
                    .ignoresSafeArea()
            #endif
        } else {
            VStack(spacing: Spacing.md) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 72))
                Text("capture.camera.samplePlaceholder", bundle: .module)
                    .font(AppFont.caption)
            }
            .foregroundStyle(AppColor.onMedia.opacity(0.6))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var focusSquare: some View {
        if let focusIndicator, viewfinderSize != .zero {
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(AppColor.onMedia, lineWidth: 1.5)
                .frame(width: 72, height: 72)
                .position(
                    x: focusIndicator.point.x * viewfinderSize.width,
                    y: focusIndicator.point.y * viewfinderSize.height
                )
                .allowsHitTesting(false)
                .task(id: focusIndicator.id) {
                    try? await Task.sleep(for: .seconds(1.2))
                    self.focusIndicator = nil
                }
        }
    }

    private var focusTapGesture: some Gesture {
        SpatialTapGesture()
            .onEnded { value in
                guard viewfinderSize != .zero else { return }
                let point = CGPoint(
                    x: min(1, max(0, value.location.x / viewfinderSize.width)),
                    y: min(1, max(0, value.location.y / viewfinderSize.height))
                )
                model.focus(at: point)
                focusIndicator = FocusIndicator(point: point)
            }
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let start = zoomStartValue ?? model.displayZoomFactor
                zoomStartValue = start
                model.setDisplayZoom(start * value.magnification)
            }
            .onEnded { _ in zoomStartValue = nil }
    }
}
