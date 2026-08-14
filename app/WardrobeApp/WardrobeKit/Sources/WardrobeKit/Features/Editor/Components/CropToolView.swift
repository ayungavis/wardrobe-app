import DesignSystem
import SwiftUI

/// Pinch resizes and drag moves the crop window over the full image.
struct CropToolView: View {
    let image: CGImage?
    let spec: CropSpec
    let onChange: (CropSpec) -> Void

    @State private var viewSize: CGSize = .zero
    @State private var baseRect: CGRect?

    var body: some View {
        if let image {
            Image(decorative: image, scale: 1)
                .resizable()
                .scaledToFit()
                .onGeometryChange(for: CGSize.self) { proxy in
                    proxy.size
                } action: { newSize in
                    viewSize = newSize
                }
                .overlay {
                    CropWindowShape(rect: denormalized(spec.rect))
                        .fill(AppColor.mediaBackground.opacity(0.5), style: FillStyle(eoFill: true))
                    Rectangle()
                        .path(in: denormalized(spec.rect))
                        .stroke(AppColor.onMedia, lineWidth: 2)
                }
                .gesture(dragGesture.simultaneously(with: magnifyGesture))
        } else {
            ProgressView()
                .tint(AppColor.onMedia)
        }
    }

    private func denormalized(_ rect: CGRect) -> CGRect {
        CGRect(
            x: rect.origin.x * viewSize.width,
            y: rect.origin.y * viewSize.height,
            width: rect.width * viewSize.width,
            height: rect.height * viewSize.height
        )
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard viewSize != .zero else { return }
                let base = baseRect ?? spec.rect
                baseRect = base
                var rect = base
                rect.origin.x += value.translation.width / viewSize.width
                rect.origin.y += value.translation.height / viewSize.height
                onChange(CropSpec(rect: rect.clampedToUnitSpace()))
            }
            .onEnded { _ in baseRect = nil }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let base = baseRect ?? spec.rect
                baseRect = base
                let width = min(1, max(0.2, base.width / value.magnification))
                let height = min(1, max(0.2, base.height / value.magnification))
                let rect = CGRect(
                    x: base.midX - width / 2,
                    y: base.midY - height / 2,
                    width: width,
                    height: height
                )
                onChange(CropSpec(rect: rect.clampedToUnitSpace()))
            }
            .onEnded { _ in baseRect = nil }
    }
}

/// Even-odd shape dimming everything outside the crop window.
private struct CropWindowShape: Shape {
    let rect: CGRect

    func path(in bounds: CGRect) -> Path {
        var path = Path()
        path.addRect(bounds)
        path.addRect(rect.intersection(bounds))
        return path
    }
}

private extension CGRect {
    /// Keeps the rect inside the unit square without changing its size.
    func clampedToUnitSpace() -> CGRect {
        var rect = self
        rect.origin.x = min(max(rect.origin.x, 0), 1 - width)
        rect.origin.y = min(max(rect.origin.y, 0), 1 - height)
        return rect
    }
}
