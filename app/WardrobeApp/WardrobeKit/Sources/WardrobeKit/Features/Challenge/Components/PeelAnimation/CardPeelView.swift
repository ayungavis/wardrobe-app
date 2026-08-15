//
//  CardPeelView.swift
//  WardrobeKit
//
//  Created by Luisa Haning Tyas on 14/08/26.
//

import UIKit

final class CardPeelView: UIView {

    var contentImage: UIImage? { didSet { setNeedsUpdate() } }
    var shadowContentImage: UIImage? { didSet { setNeedsUpdate() } }

    private(set) var fraction: CGFloat = 0 // 0 = flat, 1 = fully peeled off
    private var isReverse = false

    private let containerLayer = CALayer()
    private let shadowContainerLayer = CALayer()
    private let shadowMaskGradient = CAGradientLayer()
    private var segmentLayers: [CALayer] = []
    private var shadowSegmentLayers: [CALayer] = []

    private let inset: CGFloat = 20
    private let elevation: CGFloat = 60
    private let segmentCount = 20

    private var displayLink: CADisplayLink?
    private var animStart: CGFloat = 0
    private var animTarget: CGFloat = 0
    private var animStartTime: CFTimeInterval = 0
    private var animDuration: CFTimeInterval = 0.35
    private var animCompletion: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        layer.addSublayer(shadowContainerLayer)
        layer.addSublayer(containerLayer)
        shadowContainerLayer.mask = shadowMaskGradient
        shadowMaskGradient.startPoint = CGPoint(x: 0.5, y: 0)
        shadowMaskGradient.endPoint = CGPoint(x: 0.5, y: 1)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        rebuildLayers()
        update(fraction: fraction, reverse: isReverse)
    }

    private func setNeedsUpdate() {
        rebuildLayers()
        update(fraction: fraction, reverse: isReverse)
    }

    private func rebuildLayers() {
        guard !bounds.isEmpty, segmentLayers.count < segmentCount else { return }
        let boundingSize = CGSize(width: bounds.width + inset * 2, height: bounds.height + inset * 2)
        let segmentHeight = boundingSize.height / CGFloat(segmentCount)

        for i in 0..<segmentCount {
            let segmentLayer = CALayer()
            let shadowLayer = CALayer()
            segmentLayer.anchorPoint = .zero
            shadowLayer.anchorPoint = .zero

            let segFrame = CGRect(x: 0, y: CGFloat(i) * segmentHeight, width: boundingSize.width, height: segmentHeight)
            let contentsRect = CGRect(
                x: segFrame.minX / boundingSize.width, y: segFrame.minY / boundingSize.height,
                width: segFrame.width / boundingSize.width, height: segFrame.height / boundingSize.height
            )
            segmentLayer.contentsRect = contentsRect
            shadowLayer.contentsRect = contentsRect

            containerLayer.addSublayer(segmentLayer)
            shadowContainerLayer.addSublayer(shadowLayer)
            segmentLayers.append(segmentLayer)
            shadowSegmentLayers.append(shadowLayer)
        }
    }

    func setFraction(_ newFraction: CGFloat, reverse: Bool) {
        fraction = min(max(newFraction, 0), 1)
        isReverse = reverse
        update(fraction: fraction, reverse: reverse)
    }

    /// Animates to a target fraction using CADisplayLink — independent of SwiftUI's animation system,
    /// since this view's geometry is driven manually via CALayer transforms.
    func animate(to target: CGFloat, reverse: Bool, duration: CFTimeInterval = 0.35, completion: (() -> Void)? = nil) {
        displayLink?.invalidate()
        animStart = fraction
        animTarget = target
        isReverse = reverse
        animStartTime = CACurrentMediaTime()
        animDuration = duration
        animCompletion = completion

        let link = CADisplayLink(target: self, selector: #selector(step))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc private func step() {
        let elapsed = CACurrentMediaTime() - animStartTime
        let t = min(1, elapsed / animDuration)
        let eased = CGFloat(1 - pow(1 - t, 3)) // ease-out cubic
        setFraction(animStart + (animTarget - animStart) * eased, reverse: isReverse)

        if t >= 1 {
            displayLink?.invalidate()
            displayLink = nil
            animCompletion?()
        }
    }

    private func update(fraction: CGFloat, reverse: Bool) {
        guard !segmentLayers.isEmpty else { return }
        let segContents = contentImage?.cgImage
        let shadowContents = shadowContentImage?.cgImage ?? segContents

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        for i in 0..<segmentLayers.count {
            let segmentLayer = segmentLayers[i]
            let shadowLayer = shadowSegmentLayers[i]
            segmentLayer.contents = segContents
            shadowLayer.contents = shadowContents

            let topFraction = CGFloat(i) / CGFloat(segmentLayers.count)
            let bottomFraction = CGFloat(i + 1) / CGFloat(segmentLayers.count)
            let topZ = elevation * valueAt(fraction: fraction, t: topFraction, reverse: reverse)
            let bottomZ = elevation * valueAt(fraction: fraction, t: bottomFraction, reverse: reverse)
            let topY = -inset + topFraction * (bounds.height + inset * 2)
            let bottomY = -inset + bottomFraction * (bounds.height + inset * 2)

            let dy = bottomY - topY
            let dz = bottomZ - topZ
            let angle = -atan2(dy, dz) + .pi * 0.5

            segmentLayer.zPosition = topZ
            segmentLayer.transform = CATransform3DMakeRotation(angle, 1, 0, 0)
            shadowLayer.zPosition = segmentLayer.zPosition
            shadowLayer.transform = segmentLayer.transform

            let segHeight = sqrt(dy * dy + dz * dz)
            segmentLayer.position = CGPoint(x: -inset, y: topY)
            shadowLayer.position = segmentLayer.position
            segmentLayer.bounds = CGRect(x: 0, y: 0, width: bounds.width + inset * 2, height: segHeight)
            shadowLayer.bounds = segmentLayer.bounds
        }

        shadowMaskGradient.frame = shadowContainerLayer.bounds
        shadowMaskGradient.colors = (0...segmentLayers.count).map { i in
            let t = CGFloat(i) / CGFloat(segmentLayers.count)
            return UIColor(white: 1, alpha: valueAt(fraction: fraction, t: t, reverse: reverse)).cgColor as Any
        }
        CATransaction.commit()
    }

    private func valueAt(fraction: CGFloat, t: CGFloat, reverse: Bool) -> CGFloat {
        let windowSize: CGFloat = 0.8
        let effectiveT: CGFloat, windowStartOffset: CGFloat, windowEndOffset: CGFloat
        if reverse {
            effectiveT = 1 - t; windowStartOffset = 1; windowEndOffset = -windowSize
        } else {
            effectiveT = t; windowStartOffset = -windowSize; windowEndOffset = 1
        }
        let windowPosition = (1 - fraction) * windowStartOffset + fraction * windowEndOffset
        let windowT = max(0, min(windowSize, effectiveT - windowPosition)) / windowSize
        return 1 - windowFunction(windowT)
    }

    private func windowFunction(_ t: CGFloat) -> CGFloat {
        evaluateBezier(0.5, 0.0, 0.5, 1.0, t)
    }
}

private func evaluateBezier(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat, _ x: CGFloat) -> CGFloat {
    func coord(_ t: CGFloat, _ c1: CGFloat, _ c2: CGFloat) -> CGFloat {
        let mt = 1 - t
        return 3 * mt * mt * t * c1 + 3 * mt * t * t * c2 + t * t * t
    }
    var t = x
    for _ in 0..<8 {
        let dx = coord(t, x1, x2) - x
        if abs(dx) < 0.0001 { break }
        let d = (coord(t + 0.001, x1, x2) - coord(t - 0.001, x1, x2)) / 0.002
        if d == 0 { break }
        t -= dx / d
    }
    return coord(t, y1, y2)
}
