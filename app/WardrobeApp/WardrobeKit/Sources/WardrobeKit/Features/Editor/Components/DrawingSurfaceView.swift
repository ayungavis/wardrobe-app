import CoreGraphics
import DesignSystem
import SwiftUI

struct DrawingSurfaceView: View {
    let session: DrawingContent
    let pen: DrawingPen
    let onStrokeFinished: ([DrawingPoint]) -> Void

    @State private var points: [DrawingPoint] = []

    private let minimumPointDistance: CGFloat = 1.5

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                DrawingCanvasView(content: session, referenceWidth: proxy.size.width)
                    .allowsHitTesting(false)

                DrawingCanvasView(content: liveContent, referenceWidth: proxy.size.width)
                    .allowsHitTesting(false)

                eraserCursor(in: proxy.size)

                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .gesture(strokeGesture(in: proxy.size))
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func eraserCursor(in size: CGSize) -> some View {
        if pen.isErasing, let last = points.last {
            let diameter = CGFloat(pen.width.eraserRadius) * size.width * 2
            Circle()
                .stroke(AppColor.onMedia.opacity(0.86), lineWidth: 1.5)
                .background(Circle().fill(AppColor.mediaBackground.opacity(0.16)))
                .frame(width: diameter, height: diameter)
                .position(x: last.unitX * size.width, y: last.unitY * size.height)
                .allowsHitTesting(false)
        }
    }

    private var liveContent: DrawingContent {
        guard !pen.isErasing, !points.isEmpty else { return .empty }
        return DrawingContent(strokes: [
            DrawingStroke(points: points, color: pen.color, width: pen.width),
        ])
    }

    private func strokeGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                append(value.location, in: size)
            }
            .onEnded { value in
                append(value.location, in: size)
                let finished = points
                points.removeAll(keepingCapacity: true)
                onStrokeFinished(finished)
            }
    }

    private func append(_ location: CGPoint, in size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        guard points.count < DrawingStroke.maximumPointCount else { return }

        let point = DrawingPoint(
            unitX: min(max(location.x / size.width, 0), 1),
            unitY: min(max(location.y / size.height, 0), 1)
        )

        if let last = points.last {
            let horizontal = (point.unitX - last.unitX) * size.width
            let vertical = (point.unitY - last.unitY) * size.height
            guard horizontal * horizontal + vertical * vertical
                >= minimumPointDistance * minimumPointDistance
            else {
                return
            }
        }

        points.append(point)
    }
}
