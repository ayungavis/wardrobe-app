import SwiftUI

/// Story-style direct manipulation shared by every canvas overlay: drag to
/// move, pinch to resize, two-finger rotate. Each gesture captures a baseline
/// on its first change so repeated gestures never compound.
struct ManipulatableOverlayView<Content: View>: View {
    /// Center position in unit canvas space (0...1).
    let position: CGPoint
    let scale: CGFloat
    let rotationDegrees: Double
    let canvasSize: CGSize
    var onTap: (() -> Void)?
    let onMove: (CGPoint) -> Void
    let onScale: (CGFloat) -> Void
    let onRotate: (Double) -> Void
    let onDragActive: (Bool) -> Void
    let onManipulationEnd: () -> Void
    @ViewBuilder let content: Content

    @State private var dragStartPosition: CGPoint?
    @State private var scaleStartValue: CGFloat?
    @State private var rotationStartValue: Double?

    var body: some View {
        content
            .rotationEffect(.degrees(rotationDegrees))
            .position(
                x: position.x * canvasSize.width,
                y: position.y * canvasSize.height
            )
            .onTapGesture { onTap?() }
            .gesture(dragGesture)
            .simultaneousGesture(magnifyGesture)
            .simultaneousGesture(rotateGesture)
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard canvasSize != .zero else { return }
                let start = dragStartPosition ?? position
                if dragStartPosition == nil {
                    onDragActive(true)
                }
                dragStartPosition = start
                onMove(CGPoint(
                    x: start.x + value.translation.width / canvasSize.width,
                    y: start.y + value.translation.height / canvasSize.height
                ))
            }
            .onEnded { _ in
                dragStartPosition = nil
                onDragActive(false)
                onManipulationEnd()
            }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let start = scaleStartValue ?? scale
                scaleStartValue = start
                onScale(start * value.magnification)
            }
            .onEnded { _ in
                scaleStartValue = nil
                onManipulationEnd()
            }
    }

    private var rotateGesture: some Gesture {
        RotateGesture()
            .onChanged { value in
                let start = rotationStartValue ?? rotationDegrees
                rotationStartValue = start
                onRotate(start + value.rotation.degrees)
            }
            .onEnded { _ in
                rotationStartValue = nil
                onManipulationEnd()
            }
    }
}
