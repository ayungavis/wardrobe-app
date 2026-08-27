#if os(iOS)
    import CoreGraphics
    import SwiftUI
    import UIKit

    struct ZoomableImageView: UIViewRepresentable {
        let image: CGImage

        func makeUIView(context _: Context) -> ZoomingScrollView {
            ZoomingScrollView(image: image)
        }

        func updateUIView(_ uiView: ZoomingScrollView, context _: Context) {
            uiView.show(image)
        }
    }

    final class ZoomingScrollView: UIScrollView, UIScrollViewDelegate {
        private static let margin: CGFloat = 24

        private let content = UIImageView()
        private var laidOut: CGSize = .zero
        init(image: CGImage) {
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
    }
#endif
