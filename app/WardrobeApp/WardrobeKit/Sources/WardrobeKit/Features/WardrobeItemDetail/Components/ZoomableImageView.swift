#if os(iOS)
    import CoreGraphics
    import SwiftUI
    import UIKit

    struct ZoomableImageView: UIViewRepresentable {
        let image: CGImage
        let onDismiss: () -> Void

        func makeUIView(context _: Context) -> ZoomingScrollView {
            ZoomingScrollView(image: image, onDismiss: onDismiss)
        }

        func updateUIView(_ uiView: ZoomingScrollView, context _: Context) {
            uiView.show(image)
            uiView.onDismiss = onDismiss
        }
    }

    final class ZoomingScrollView: UIScrollView, UIScrollViewDelegate, UIGestureRecognizerDelegate {
        private static let margin: CGFloat = 24
        private static let dismissAfter: CGFloat = 120

        private let content = UIImageView()
        private var laidOut: CGSize = .zero
        var onDismiss: () -> Void

        init(image: CGImage, onDismiss: @escaping () -> Void) {
            self.onDismiss = onDismiss
            super.init(frame: .zero)

            content.contentMode = .scaleAspectFit
            content.image = UIImage(cgImage: image)
            addSubview(content)

            delegate = self
            minimumZoomScale = 1
            maximumZoomScale = 4
            showsHorizontalScrollIndicator = false
            showsVerticalScrollIndicator = false
            backgroundColor = .clear

            let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap))
            doubleTap.numberOfTapsRequired = 2
            addGestureRecognizer(doubleTap)

            let drag = UIPanGestureRecognizer(target: self, action: #selector(handleDrag))
            drag.delegate = self
            addGestureRecognizer(drag)
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("ZoomingScrollView is built in code")
        }

        func show(_ image: CGImage) {
            guard content.image?.cgImage !== image else { return }
            content.image = UIImage(cgImage: image)
            zoomScale = minimumZoomScale
            laidOut = .zero
            setNeedsLayout()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            guard bounds.size != .zero else { return }

            if bounds.size != laidOut {
                laidOut = bounds.size
                zoomScale = minimumZoomScale
                content.transform = .identity
                content.frame = CGRect(
                    origin: .zero, size: ZoomLayout.fitted(in: bounds.size, margin: Self.margin)
                )
                contentSize = content.frame.size
            }
            centreContent()
        }

        private func centreContent() {
            let insets = ZoomLayout.centring(bounds: bounds.size, content: content.frame.size)
            contentInset = UIEdgeInsets(
                top: insets.vertical, left: insets.horizontal,
                bottom: insets.vertical, right: insets.horizontal
            )
        }

        // MARK: Zooming

        func viewForZooming(in _: UIScrollView) -> UIView? {
            content
        }

        func scrollViewDidZoom(_: UIScrollView) {
            centreContent()
        }

        @objc private func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
            guard zoomScale == minimumZoomScale else {
                setZoomScale(minimumZoomScale, animated: true)
                return
            }
            let point = recognizer.location(in: content)
            let side = bounds.width / 2
            zoom(
                to: CGRect(x: point.x - side / 2, y: point.y - side / 2, width: side, height: side),
                animated: true
            )
        }

        // MARK: Drag to dismiss

        // ponytail: the transform is also what the scroll view drives while zooming,
        // so the zoomScale guard is what keeps the two off each other. Move the
        // drag onto a wrapper view if they ever need to run together.
        @objc private func handleDrag(_ recognizer: UIPanGestureRecognizer) {
            guard zoomScale == minimumZoomScale else { return }
            let translation = recognizer.translation(in: self)

            switch recognizer.state {
            case .changed:
                guard translation.y > 0 else { return }
                let shrink = max(0.8, 1 - translation.y / (bounds.height * 2))
                content.transform = CGAffineTransform(translationX: translation.x, y: translation.y)
                    .scaledBy(x: shrink, y: shrink)
            case .ended, .cancelled, .failed:
                guard translation.y > Self.dismissAfter else {
                    UIView.animate(withDuration: 0.25) { self.content.transform = .identity }
                    return
                }
                onDismiss()
            default:
                break
            }
        }

        func gestureRecognizer(
            _: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
#endif
