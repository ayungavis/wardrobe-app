import CoreGraphics

enum CropGeometry {
    static let photoAspectRatio: CGFloat = 3.0 / 4.0

    static let scaleRange: ClosedRange<CGFloat> = 1 ... 6

    static func cropSize(
        fitting available: CGSize,
        insets: CGSize,
        aspectRatio: CGFloat = photoAspectRatio
    ) -> CGSize {
        let maxWidth = max(0, available.width - insets.width)
        let maxHeight = max(0, available.height - insets.height)

        var width = maxWidth
        var height = width / aspectRatio
        if height > maxHeight {
            height = maxHeight
            width = height * aspectRatio
        }
        return CGSize(width: width, height: height)
    }

    static func aspectFillSize(imageSize: CGSize, cropSize: CGSize) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0, cropSize.height > 0 else {
            return cropSize
        }

        let imageAspect = imageSize.width / imageSize.height
        let cropAspect = cropSize.width / cropSize.height

        return imageAspect > cropAspect
            ? CGSize(width: cropSize.height * imageAspect, height: cropSize.height)
            : CGSize(width: cropSize.width, height: cropSize.width / imageAspect)
    }

    static func clampedScale(_ value: CGFloat) -> CGFloat {
        min(max(value, scaleRange.lowerBound), scaleRange.upperBound)
    }

    static func clampedOffset(
        _ proposed: CGSize,
        scale: CGFloat,
        imageSize: CGSize,
        cropSize: CGSize
    ) -> CGSize {
        let displayed = displayedSize(imageSize: imageSize, cropSize: cropSize, scale: scale)
        let limitX = max(0, (displayed.width - cropSize.width) / 2)
        let limitY = max(0, (displayed.height - cropSize.height) / 2)

        return CGSize(
            width: min(max(proposed.width, -limitX), limitX),
            height: min(max(proposed.height, -limitY), limitY)
        )
    }

    static func offset(_ offset: CGSize, rescaledFrom old: CGFloat, to new: CGFloat) -> CGSize {
        guard old > 0, new > 0 else { return offset }
        let ratio = new / old
        return CGSize(width: offset.width * ratio, height: offset.height * ratio)
    }

    static func normalizedRect(
        scale: CGFloat,
        offset: CGSize,
        imageSize: CGSize,
        cropSize: CGSize
    ) -> CGRect {
        let displayed = displayedSize(imageSize: imageSize, cropSize: cropSize, scale: scale)
        guard displayed.width > 0, displayed.height > 0 else {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }

        let safeOffset = clampedOffset(offset, scale: scale, imageSize: imageSize, cropSize: cropSize)
        let origin = CGPoint(
            x: (displayed.width - cropSize.width) / 2 - safeOffset.width,
            y: (displayed.height - cropSize.height) / 2 - safeOffset.height
        )

        return CGRect(
            x: origin.x / displayed.width,
            y: origin.y / displayed.height,
            width: cropSize.width / displayed.width,
            height: cropSize.height / displayed.height
        ).standardized
    }

    struct Framing: Equatable {
        let scale: CGFloat
        let offset: CGSize
    }

    static func framing(for rect: CGRect, imageSize: CGSize, cropSize: CGSize) -> Framing {
        let fill = aspectFillSize(imageSize: imageSize, cropSize: cropSize)
        guard rect.width > 0, rect.height > 0, fill.width > 0, fill.height > 0 else {
            return Framing(scale: 1, offset: .zero)
        }

        let scale = clampedScale(cropSize.width / rect.width / fill.width)
        let displayed = CGSize(width: fill.width * scale, height: fill.height * scale)
        let offset = CGSize(
            width: (displayed.width - cropSize.width) / 2 - rect.minX * displayed.width,
            height: (displayed.height - cropSize.height) / 2 - rect.minY * displayed.height
        )

        return Framing(
            scale: scale,
            offset: clampedOffset(offset, scale: scale, imageSize: imageSize, cropSize: cropSize)
        )
    }

    private static func displayedSize(imageSize: CGSize, cropSize: CGSize, scale: CGFloat) -> CGSize {
        let base = aspectFillSize(imageSize: imageSize, cropSize: cropSize)
        return CGSize(width: base.width * scale, height: base.height * scale)
    }
}
