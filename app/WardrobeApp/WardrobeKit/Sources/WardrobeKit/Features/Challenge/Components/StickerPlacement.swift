//
//  StickerPlacement.swift
//  WardrobeKit
//
//  Created by Luisa Haning Tyas on 16/08/26.
//


import Foundation

struct StickerPlacement: Identifiable {
    let id = UUID()
    let imageName: String
    let x: CGFloat            // fraction 0-1, relative to its container
    let y: CGFloat
    let widthFraction: CGFloat
    let rotation: Double      // degrees, 0 if none

    /// Fraction-based initializer — use this if you've already computed 0-1 values yourself.
    init(_ imageName: String, x: CGFloat, y: CGFloat, width: CGFloat, rotation: Double = 0) {
        self.imageName = imageName
        self.x = x
        self.y = y
        self.widthFraction = width
        self.rotation = rotation
    }

    /// Figma-pixel-based initializer — paste the sticker's raw px position/size from Figma's
    /// inspector, along with the frame's total px width/height, and this does the fraction math for you.
    ///
    /// In Figma: select the sticker, note its X/Y (top-left corner, relative to its parent frame)
    /// and Width. Also note the parent frame's total Width/Height (e.g. your card frame, or your
    /// whole screen frame — whichever this sticker is nested inside).
    init(
        _ imageName: String,
        figmaX: CGFloat,
        figmaY: CGFloat,
        figmaWidth: CGFloat,
        figmaHeight: CGFloat,
        frameWidth: CGFloat,
        frameHeight: CGFloat,
        rotation: Double = 0
    ) {
        self.imageName = imageName
        self.x = (figmaX + figmaWidth / 2) / frameWidth
        self.y = (figmaY + figmaHeight / 2) / frameHeight
        self.widthFraction = figmaWidth / frameWidth
        self.rotation = rotation
    }
}
